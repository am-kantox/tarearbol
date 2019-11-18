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
          (() -> any()) | {module(), atom(), list()},
          Tarearbol.Utils.interval(),
          keyword()
        ) :: Task.t()
  def run_in(job, interval, opts \\ opts()) do
    Tarearbol.Application.task!(fn ->
      waiting_time = Tarearbol.Utils.interval(interval, value: 0)

      Process.put(:job, {job, Tarearbol.Utils.add_interval(interval), opts})
      Process.sleep(waiting_time)
      result = Tarearbol.Job.ensure(job, opts)
      Process.delete(:job)

      cond do
        #! TODO deal with attempts above and rerun unless success
        # opts[:sidekiq] -> run_in(job, sidekiq_interval(waiting_time), opts)
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
  @spec run_at(Tarearbol.Job.job(), %DateTime{}, keyword()) :: %Task{
          :owner => pid(),
          :pid => nil | pid(),
          :ref => reference()
        }
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
  @spec spawn((() -> any()) | {module(), atom(), list()}, keyword()) :: Task.t()
  def spawn(job, opts \\ opts()), do: run_in(job, :none, opts)

  ##############################################################################

  @spec opts() :: keyword()
  defp opts, do: Application.get_env(:tarearbol, :errand_options, @default_opts)

  @spec run_in_opts(keyword()) :: keyword()
  defp run_in_opts(opts), do: Keyword.delete(opts, :repeatedly)
end
