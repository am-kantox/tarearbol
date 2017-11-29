defmodule Tarearbol.Errand do
  @moduledoc false

  require Logger

  @default_opts [
    repeatedly: false
  ]
  @msecs_per_day 1_000 * 60 * 60 * 24

  @doc """
  Runs the task either once at the specified `%DateTime{}` or repeatedly
    at the specified `%Time{}`.
  """
  @spec run_in(
          Function.t() | {Module.t(), Atom.t(), List.t()},
          Tarearbol.Utils.interval(),
          Keyword.t()
        ) :: Task.t()
  def run_in(job, interval, opts \\ opts()) do
    Tarearbol.Application.task!(fn ->
      waiting_time = Tarearbol.Utils.interval(interval, value: 0)
      task_details = {job, interval_to_datetime(waiting_time), opts}

      Process.put(:job, {job, Tarearbol.Utils.add_interval(interval), opts})
      Tarearbol.Cron.put_task(task_details)
      Process.sleep(waiting_time)
      result = Tarearbol.Job.ensure(job, opts)
      Tarearbol.Cron.del_task(task_details)
      Process.delete(:job)

      cond do
        opts[:sidekiq] -> run_in(job, sidekiq_interval(waiting_time), opts)
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
  @spec run_at(
          Function.t() | {Module.t(), Atom.t(), List.t()},
          DateTime.t() | Time.t() | String.t(),
          Keyword.t()
        ) :: Task.t()
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

  def run_at(job, at, opts) when is_binary(at), do: run_at(job, DateTime.from_iso8601(at), opts)

  @doc "Spawns the task by calling `run_in` with a zero interval"
  @spec spawn(Function.t() | {Module.t(), Atom.t(), List.t()}, Keyword.t()) :: Task.t()
  def spawn(job, opts \\ opts()), do: run_in(job, :none, opts)

  ##############################################################################

  @spec opts() :: Keyword.t()
  defp opts, do: Application.get_env(:tarearbol, :errand_options, @default_opts)

  @spec run_in_opts(Keyword.t()) :: Keyword.t()
  defp run_in_opts(opts), do: Keyword.delete(opts, :repeatedly)

  # to perform 25 times in 21 day
  @mike_perham_const 1.15647559215

  @spec sidekiq_interval(Integer.t()) :: Integer.t()
  defp sidekiq_interval(interval),
    do: @mike_perham_const * interval * :math.atan(:math.log(interval))

  defp interval_to_datetime(msecs) do
    DateTime.utc_now()
    |> DateTime.to_unix(:millisecond)
    |> Kernel.+(msecs)
    |> DateTime.from_unix!(:millisecond)
  end
end
