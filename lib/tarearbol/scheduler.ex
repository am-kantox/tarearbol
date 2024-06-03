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
      Tarearbol.DynamicManager,
      Tarearbol.InternalWorker,
      Tarearbol.Telemetria
    ],
    exports: [State]

  require Logger
  use Tarearbol.DynamicManager

  @typedoc """
  Type of the job runner, an `{m, f}` tuple or a function of arity zero,
  returning one of the outcomes below
  """
  @type runner ::
          {atom(), atom()}
          | {atom(), atom(), list()}
          | (-> :halt | {:ok | {:reschedule, binary()}, any()})

  @typedoc """
  Type of possible job schedules to be run repeatedly: binary cron format
  or `DateTime` for the daily execution
  """
  @type repeated_schedule :: binary() | DateTime.t()
  @typedoc """
  Type of possible job schedules to be run once: `Time` to be executed once or
  amount of milliseconds to execute after
  """
  @type once_schedule :: non_neg_integer() | Time.t()
  @typedoc "Combined type for the all schedules possible"
  @type schedule :: once_schedule() | repeated_schedule()

  defmodule Job do
    @moduledoc """
    A struct holding the job description. Used internally by `Tarearbol.Scheduler`
    to preserve a list of scheduled jobs.
    """

    alias Tarearbol.Scheduler

    @typedoc "The struct containing the information about the job"
    @type t :: %{
            __struct__: Job,
            name: binary(),
            runner: Scheduler.runner(),
            schedule: Scheduler.repeated_schedule(),
            once?: boolean()
          }

    defstruct [:name, :runner, :schedule, :once?]

    @spec normalize_schedule(Scheduler.schedule()) :: DateTime.t() | binary()
    defp normalize_schedule(schedule) do
      case schedule do
        msecs when is_integer(msecs) ->
          DateTime.add(DateTime.utc_now(), schedule, :millisecond)

        %Time{} = time ->
          DateTime.new!(Date.utc_today(), time)

        %DateTime{} = hour_x ->
          hour_x

        crontab when is_binary(crontab) ->
          crontab
      end
    end

    @doc "Produces a `Tarearbol.Scheduler.Job` by parameters given"
    @spec create(
            name :: binary(),
            runner :: Scheduler.runner(),
            schedule :: Scheduler.repeated_schedule() | Scheduler.once_schedule()
          ) :: t()
    def create(name, runner, schedule) do
      schedule = normalize_schedule(schedule)
      once? = match?(%DateTime{}, schedule)
      struct(Job, name: name, runner: runner, schedule: schedule, once?: once?)
    end
  end

  use Tarearbol.Telemetria

  @impl Tarearbol.DynamicManager
  @doc false
  def children_specs,
    do: for({name, runner, schedule} <- jobs(), into: %{}, do: job!(name, runner, schedule))

  @impl Tarearbol.DynamicManager
  @doc false
  def perform(id, %{job: %Job{}} = payload),
    do: do_perform(id, payload)

  if Tarearbol.Telemetria.use?(), do: @telemetria(Tarearbol.Telemetria.apply_options())
  @spec do_perform(id :: Tarearbol.DynamicManager.id(), payload :: map()) :: any()
  defp do_perform(id, %{job: %Job{}} = payload) do
    job = payload.job

    result =
      case job.runner do
        {m, f, a} -> apply(m, f, a)
        {m, f} -> apply(m, f, [])
        f when is_function(f, 0) -> f.()
      end

    Logger.info("[🌴] Job ##{job.name} has been performed: #{inspect(result)}")

    case {job.once?, result} do
      {true, _} ->
        :halt

      {_, :halt} ->
        :halt

      {_, {:ok, result}} ->
        {{:timeout, timeout(job.schedule)}, result}

      {_, {{:reschedule, schedule}, _result}} ->
        {:replace, id, %{payload | job: %Job{job | schedule: schedule}}}

      {_, result} ->
        Logger.warning(
          "[🌴] Unexpected return from the job: #{inspect(result)}, must be :halt, or {:ok, _}, or {{:reschedule, _}, _}"
        )

        {{:timeout, timeout(job.schedule)}, result}
    end
  end

  @spec active_jobs :: %{Tarearbol.DynamicManager.id() => Tarearbol.DynamicManager.Child.t()}
  def active_jobs, do: state().children

  @doc """
  Creates and temporarily pushes the job to the list of currently scheduled jobs.

  For the implementation that survives restarts use `push!/3`.
  """
  @spec push(
          name :: binary(),
          runner :: runner(),
          schedule :: repeated_schedule() | once_schedule()
        ) :: :ok
  def push(name, runner, schedule) do
    {name, opts} = job!(name, runner, schedule)
    Tarearbol.Scheduler.put(name, opts)
  end

  @doc """
  Creates and pushes the job to the list of currently scheduled jobs, updates
  the permanent list of scheduled jobs.

  For the implementation that temporarily pushes a job, use `push/3`.
  """
  @spec push!(
          name :: binary(),
          runner :: runner(),
          schedule :: repeated_schedule() | once_schedule()
        ) :: :ok
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

  @spec job!(name :: any(), runner :: runner(), schedule :: repeated_schedule() | once_schedule()) ::
          {binary(), map()}
  defp job!(name, runner, schedule) do
    job = Job.create(name, runner, schedule)

    {inspect(name), %{payload: %{job: job}, timeout: timeout(job.schedule)}}
  end

  @spec timeout(schedule :: repeated_schedule()) :: non_neg_integer()
  defp timeout(schedule) when is_binary(schedule),
    do: DateTime.add(DateTime.utc_now(), 1, :second)

  defp timeout(%DateTime{} = schedule),
    do: Enum.max([0, DateTime.diff(schedule, DateTime.utc_now(), :millisecond)])

  @spec config :: keyword()
  defp config,
    do:
      if(Code.ensure_loaded?(Mix),
        do: Keyword.get(Mix.Project.config(), :tarearbol, []),
        else: []
      )

  @spec config_file :: binary()
  defp config_file, do: Keyword.get(config(), :jobs_file, ".tarearbol.exs")

  @spec jobs :: [{any(), runner(), repeated_schedule() | once_schedule()}]
  defp jobs do
    Application.get_env(:tarearbol, :jobs, []) ++
      Keyword.get(config(), :jobs, []) ++
      if File.exists?(config_file()),
        do: config_file() |> File.read!() |> Code.eval_string(),
        else: []
  end
end
