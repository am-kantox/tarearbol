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
  This won’t work with releases.

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

  use Boundary,
    deps: [
      Tarearbol.Crontab,
      Tarearbol.DynamicManager,
      Tarearbol.InternalWorker,
      Tarearbol.Telemetria
    ],
    exports: [State]

  use Tarearbol.DynamicManager

  @typedoc """
  Type of the job runner, an `{m, f}` tuple or a function of arity zero,
  returning one of the outcomes below
  """
  @type runner ::
          {atom(), atom()} | (() -> :halt | {:ok | {:reschedule, binary()}, any()})

  @typedoc """
  Type of possible job schedules: binary cron format, `Time` to be executed once
  `DateTime` for the daily execution
  """
  @type schedule :: binary() | non_neg_integer() | DateTime.t() | Time.t()

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
            schedule :: Tarearbol.Scheduler.schedule()
          ) :: t()
    def create(name, runner, schedule) do
      {once?, schedule} =
        case schedule do
          msecs when is_integer(msecs) ->
            {true, Macro.escape(DateTime.add(DateTime.utc_now(), schedule, :millisecond))}

          %Time{} ->
            {false, Tarearbol.Crontab.to_cron(schedule)}

          %DateTime{} = hour_x ->
            {true, Macro.escape(hour_x)}

          crontab when is_binary(crontab) ->
            {false, crontab}
        end

      run_ast =
        case runner do
          {m, f} ->
            quote bind_quoted: [once?: once?, m: m, f: f] do
              def run do
                result = apply(m, f, [])
                if once?, do: :halt, else: {:ok, result}
              end
            end

          f when is_function(f, 0) ->
            f = Macro.escape(f)

            quote do
              def run do
                result = unquote(f).()
                if unquote(once?), do: :halt, else: {:ok, result}
              end
            end
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

  Tarearbol.Telemetria.maybe()

  @impl Tarearbol.DynamicManager
  @doc false
  def children_specs,
    do: for({name, runner, schedule} <- jobs(), into: %{}, do: job!(name, runner, schedule))

  @impl Tarearbol.DynamicManager
  @doc false
  def perform(id, %{job: %Job{}} = payload),
    do: do_perform(id, payload)

  @spec do_perform(id :: Tarearbol.DynamicManager.id(), payload :: map()) :: any()
  if Tarearbol.Telemetria.use?(), do: @telemetria(Tarearbol.Telemetria.apply_options())

  defp do_perform(id, payload) do
    job = payload.job

    case job.runner.() do
      :halt ->
        :halt

      {:ok, result} ->
        {{:timeout, timeout(job.schedule)}, result}

      {{:reschedule, schedule}, _result} ->
        {:replace, id, %{payload | job: %Job{job | schedule: schedule}}}
    end
  end

  @spec active_jobs :: %{atom() => %Tarearbol.DynamicManager.Child{}}
  def active_jobs, do: state().children

  @doc """
  Creates and temporarily pushes the job to the list of currently scheduled jobs.

  For the implementation that survives restarts use `push!/3`.
  """
  @spec push(name :: binary(), runner :: runner(), schedule :: schedule()) :: :ok
  def push(name, runner, schedule) do
    {name, opts} = job!(name, runner, schedule)
    Tarearbol.Scheduler.put(name, opts)
  end

  @doc """
  Creates and pushes the job to the list of currently scheduled jobs, updates
  the permanent list of scheduled jobs.

  For the implementation that temporarily pushes a job, use `push/3`.
  """
  @spec push!(name :: binary(), runner :: runner(), schedule :: schedule()) :: :ok
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

  @spec job!(name :: any(), runner :: runner(), schedule :: schedule()) :: {binary(), map()}
  defp job!(name, runner, schedule) do
    job = Job.create(name, runner, schedule)

    {inspect(name), %{payload: %{job: job}, timeout: timeout(job.schedule)}}
  end

  @spec timeout(schedule :: schedule()) :: non_neg_integer()
  defp timeout(schedule) when is_integer(schedule) and schedule > 0, do: schedule

  defp timeout(schedule) when is_binary(schedule),
    do:
      Tarearbol.Crontab.next(DateTime.utc_now(), schedule, precision: :millisecond)[:millisecond]

  defp timeout(%DateTime{} = schedule),
    do: Enum.max([0, DateTime.diff(schedule, DateTime.utc_now(), :millisecond)])

  defp timeout(%Time{} = schedule) do
    schedule
    |> Time.diff(Time.utc_now(), :millisecond)
    |> case do
      secs when secs >= 0 -> secs
      secs -> 24 * 60 * 60 + secs
    end
    |> timeout()
  end

  @spec config :: keyword()
  defp config,
    do:
      if(Code.ensure_loaded?(Mix), do: Keyword.get(Mix.Project.config(), :tarearbol, []), else: [])

  @spec config_file :: binary()
  defp config_file, do: Keyword.get(config(), :jobs_file, ".tarearbol.exs")

  @spec jobs :: [{any(), runner(), schedule()}]
  defp jobs do
    Application.get_env(:tarearbol, :jobs, []) ++
      Keyword.get(config(), :jobs, []) ++
      if File.exists?(config_file()),
        do: config_file() |> File.read!() |> Code.eval_string(),
        else: []
  end
end
