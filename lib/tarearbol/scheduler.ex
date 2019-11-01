defmodule Tarearbol.Scheduler do
  @moduledoc """
  Cron-like task scheduler. Accepts both static and dynamic configurations.

  ### Usage

  Add `Tarearbol.Scheduler` to the list of supervised workers. It would attempt
  to read the static configuration (see below) and start the `DynamicSupervisor`
  with all the scheduled jobs as supervised workers.

  The `runner` is the function of arity zero, that should return `{:ok, result}`
  tuple upon completion. The job will be rescheduled according to its schedule.

  The last result returned will be stored in the state and might be retrieved
  later with `get/1` passing the job name.

  ### Static Configuration

  Upon starts it looks up `:tarearbol` section of `Mix.Project` for
  `:jobs` and `:jobs_file` keys. The latter has a default `.tarearbol.exs`.

  Also it looks up `:tarearbol, :jobs` section of `config.exs`. Everything found
  is unioned. Jobs with the same names are overriden, the file has precedence
  over project config, the application config has least precedence.

  If found, jobs as a list of tuples of `{name, runner, schedule}` are scheduled.
  These are expected to be in the following form.

  - `name` might be whatever, used to refer to the job during it’s lifetime
  - `runner` might be either `{module, function}` tuple or a reference to the function of arity zero (`&Foo.bar/0`)
  - `schedule` in standard cron notation, see https://crontab.guru

  ### Dynamic Configuration

  Use `Tarearbol.Scheduler.push/3`, `Tarearbol.Scheduler.pop/1` to add/remove jobs
  temporarily and/or `Tarearbol.Scheduler.push!/3`, `Tarearbol.Scheduler.pop!/1` to
  reflect changes in the configuration file.

  ```elixir
  Tarearbol.Scheduler.push(TestJob, &Foo.bar/0, "3-5/1 9-18 * * 6-7")
  ```
  """
  use Tarearbol.DynamicManager

  @typedoc """
  Type of the job runner, an `{m, f}` tuple or a function of arity zero,
  returning one of the outcomes below
  """
  @type runner ::
          {atom(), atom()} | (() -> :halt | {:ok, any()} | {{:reschedule, binary()}, any()})

  defmodule Job do
    @moduledoc """
    A struct holding the job description. Used internally by `Tarearbol.Scheduler`
    to preserve a list of scheduled jobs.
    """

    @typedoc "The struct containing the information about the job"
    @type t :: %Job{}

    defstruct [:name, :module, :runner, :schedule]

    @doc "The implementation to be run on schedule"
    @callback run :: Tarearbol.Scheduler.runner()

    @doc "Produces a `Tarearbol.Scheduler.Job` by parameters given"
    @spec create(
            name :: binary(),
            runner :: Tarearbol.Scheduler.runner(),
            schedule :: binary()
          ) :: t()
    def create(name, runner, schedule) do
      run_ast =
        case runner do
          {m, f} -> quote do: def(run, do: apply(unquote(m), unquote(f), []))
          f when is_function(f, 0) -> quote do: def(run, do: unquote(f).())
        end

      ast = [
        quote do
          @behaviour Job

          @job struct(Job,
                 name: unquote(name),
                 module: __MODULE__,
                 runner: &__MODULE__.run/0,
                 schedule: unquote(schedule)
               )

          def job, do: @job
        end,
        run_ast
      ]

      with {:module, module, _, _} <-
             Module.create(Module.concat(Tarearbol.Scheduler.Job, name), ast, __ENV__),
           do: module.job()
    end
  end

  @impl Tarearbol.DynamicManager
  def children_specs,
    do: for({name, runner, schedule} <- jobs(), into: %{}, do: job!(name, runner, schedule))

  @impl Tarearbol.DynamicManager
  @doc false
  def perform(id, %{job: %Job{} = job} = payload) do
    data = Map.from_struct(job)

    case job.runner.() do
      :halt ->
        Tarearbol.Publisher.publish(:slack, :warn, Map.put(data, :status, :halted))
        :halt

      {:ok, result} ->
        data =
          data
          |> Map.put(:status, :ran)
          |> Map.put(:result, result)

        Tarearbol.Publisher.publish(:slack, :info, data)

        {{:timeout,
          Tarearbol.Crontab.next(DateTime.utc_now(), job.schedule, precision: :millisecond)[
            :millisecond
          ]}, result}

      {{:reschedule, schedule}, result} ->
        data =
          data
          |> Map.put(:status, :rescheduled)
          |> Map.put(:result, result)

        Tarearbol.Publisher.publish(:slack, :info, data)
        {:replace, id, %{payload | job: %Job{job | schedule: schedule}}}
    end
  end

  @doc """
  Creates and temporarily pushes the job to the list of currently scheduled jobs.

  For the implementation that survives restarts use `push!/3`.
  """
  @spec push(name :: any(), runner :: runner(), schedule :: binary()) :: pid()
  def push(name, runner, schedule) do
    {name, opts} = job!(name, runner, schedule)
    Tarearbol.Scheduler.put(name, opts)
  end

  @doc """
  Creates and pushes the job to the list of currently scheduled jobs, updates
  the permanent list of scheduled jobs.

  For the implementation that temporarily pushes a job, use `push/3`.
  """
  @spec push!(name :: any(), runner :: runner(), schedule :: binary()) :: pid()
  def push!(name, runner, schedule) do
    File.write!(config_file(), Macro.to_string([{name, runner, schedule} | jobs()]))
    push(name, runner, schedule)
  end

  @doc """
  Removes the scheduled job from the schedule by `id`.

  For the implementation that survives restarts use `pop!/1`.
  """
  @spec pop(name :: any()) :: :ok
  def pop(name), do: Tarearbol.Scheduler.del(name)

  @doc """
  Removes the scheduled job from the schedule by `id` and updated the configuration.

  For the implementation that removes jobs temporarily, use `pop!/1`.
  """
  @spec pop!(name :: any()) :: :ok
  def pop!(name) do
    File.write!(
      config_file(),
      Macro.to_string(for({id, _, _} = job <- jobs(), id != name, do: job))
    )

    pop(name)
  end

  @spec job!(name :: any(), runner :: runner(), schedule :: binary()) :: {binary(), map()}
  defp job!(name, runner, schedule) do
    job = Job.create(name, runner, schedule)

    timeout =
      Tarearbol.Crontab.next(DateTime.utc_now(), job.schedule, precision: :millisecond)[
        :millisecond
      ]

    {name, %{payload: %{job: job}, timeout: timeout}}
  end

  @spec config :: keyword()
  defp config, do: Keyword.get(Mix.Project.config(), :tarearbol, [])

  @spec config_file :: binary()
  defp config_file, do: Keyword.get(config(), :jobs_file, ".tarearbol.exs")

  @spec jobs :: [{any(), runner(), binary()}]
  defp jobs do
    Application.get_env(:tarearbol, :jobs, []) ++
      Keyword.get(config(), :jobs, []) ++
      if File.exists?(config_file()),
        do: config_file() |> File.read!() |> Code.eval_string(),
        else: []
  end
end
