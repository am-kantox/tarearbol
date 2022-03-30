defmodule Tarearbol.Errand do
  @moduledoc false

  use Boundary, deps: [Tarearbol.Application, Tarearbol.Job, Tarearbol.Scheduler, Tarearbol.Utils]

  require Logger

  @typep job :: (() -> any()) | {module(), atom()}

  @default_opts [
    repeatedly: false
  ]
  @msecs_per_day 1_000 * 60 * 60 * 24

  @doc """
  Runs the task either once at the specified `%DateTime{}` or repeatedly
    at the specified `%Time{}`.
  """
  @spec run_in(job(), Tarearbol.Utils.interval(), keyword()) :: :ok | Task.t()
  def run_in(job, interval, opts \\ opts()) do
    type =
      if is_function(job, 0) and Function.info(job, :type) == {:type, :local},
        do: :local,
        else: :external

    do_run_in(type, job, interval, opts)
  end

  @spec do_run_in(:local | :external, job(), Tarearbol.Utils.interval(), keyword()) ::
          :ok | Task.t()
  defp do_run_in(:external, job, interval, opts) do
    {name, _opts} = Keyword.pop(opts, :name, Tarearbol.Utils.random_module_name("Job"))

    Tarearbol.Scheduler.push(
      name,
      job,
      Tarearbol.Utils.interval(interval, value: 0)
    )
  end

  @deprecated "Use external function or `{m, f}` or `{m, f, a}` tuple as the job instead"
  defp do_run_in(:local, job, interval, opts) do
    Logger.debug(
      "[DEPRECATED] spawning local functions is deprecated; use external function or `{m, f}` or `{m, f, a}` tuple as the job instead"
    )

    Tarearbol.Application.task!(fn ->
      waiting_time = Tarearbol.Utils.interval(interval, value: 0)

      Process.put(:job, {job, Tarearbol.Utils.add_interval(interval), opts})
      Process.sleep(waiting_time)
      result = Tarearbol.Job.ensure(job, opts)
      Process.delete(:job)

      cond do
        opts[:next_run] -> run_at(job, opts[:next_run], opts)
        opts[:repeatedly] -> run_in(job, interval, opts)
        true -> result
      end
    end)
  end

  @doc """
  Runs the task either once at the specified `%DateTime{}` or repeatedly
    at the specified `%Time{}`.
  """
  @spec run_at(Tarearbol.Job.job(), DateTime.t(), keyword()) :: :ok | Task.t()
  def run_at(job, at, opts \\ opts())

  def run_at(job, %DateTime{} = at, opts) do
    interval = DateTime.diff(at, DateTime.utc_now(), :millisecond)
    run_in(job, interval, run_in_opts(opts))
  end

  def run_at(job, %Time{} = at, opts) do
    next =
      case Time.diff(at, Time.utc_now(), :millisecond) do
        # tomorrow at that time
        msec when msec <= 0 ->
          msec + @msecs_per_day

        msec ->
          msec
      end

    opts =
      opts
      |> Keyword.put_new(:next_run, at)
      |> run_in_opts()

    run_in(job, next, opts)
  end

  def run_at(job, at, opts) when is_binary(at),
    do: run_at(job, DateTime.from_iso8601(at), opts)

  @doc "Spawns the task by calling `run_in` with a zero interval"
  @spec spawn((() -> any()) | {module(), atom(), list()}, keyword()) :: :ok | Task.t()
  def spawn(job, opts \\ opts()), do: run_in(job, :none, opts)

  ##############################################################################

  @spec opts() :: keyword()
  defp opts, do: Application.get_env(:tarearbol, :default_scheduler_options, @default_opts)

  @spec run_in_opts(keyword()) :: keyword()
  defp run_in_opts(opts), do: Keyword.delete(opts, :repeatedly)
end
