defmodule Tarearbol.Errand do
  @moduledoc """
  Handy set of cron-like functions to run tasks at the specified date/time.
  """

  require Logger

  @default_opts [
    repeatedly: false
  ]
  @msecs_per_day 1_000 * 60 * 60 * 24

  @doc """
  Runs the task either once at the specified `%DateTime{}` or repeatedly
    at the specified `%Time{}`.
  """
  @spec run_in(Function.t | {Module.t, Atom.t, List.t},
               Tarearbol.Utils.interval, Keyword.t) :: Task.t
  def run_in(job, interval, opts \\ opts()) do
    Tarearbol.Application.task!(fn ->
      Process.put(:job, {job, opts, Tarearbol.Utils.add_interval(interval)})
      Process.sleep(Tarearbol.Utils.interval(interval, value: 0))
      Tarearbol.Job.ensure(job, opts)
      Process.delete(:job)

      if opts[:repeatedly], do: run_in(job, interval, opts)
      if opts[:next_run], do: run_at(job, opts[:next_run], opts)
    end)
  end

  @doc """
  Runs the task either once at the specified `%DateTime{}` or repeatedly
    at the specified `%Time{}`.
  """
  @spec run_at(Function.t | {Module.t, Atom.t, List.t},
               DateTime.t | Time.t | String.t, Keyword.t) :: Task.t
  def run_at(job, at, opts \\ opts())
  def run_at(job, %DateTime{} = at, opts) do
    interval = DateTime.diff(at, DateTime.utc_now, :millisecond)
    run_in(job, interval, run_in_opts(opts))
  end
  def run_at(job, %Time{} = at, opts) do
    next =
      case Time.diff(at, Time.utc_now, :millisecond) do
        msec when msec <= 0 -> msec + @msecs_per_day # tomorrow at that time
        msec -> msec
      end
    opts = opts
           |> Keyword.put_new(:next_run, at)
           |> run_in_opts()
    run_in(job, next, opts)
  end
  def run_at(job, at, opts) when is_binary(at),
    do: run_at(job, DateTime.from_iso8601(at), opts)

  @doc "Spawns the task by calling `run_in` with a zero interval"
  @spec spawn(Function.t | {Module.t, Atom.t, List.t}, Keyword.t) :: Task.t
  def spawn(job, opts \\ opts()), do: run_in(job, :none, opts)

  ##############################################################################

  @spec opts() :: Keyword.t
  defp opts, do: Application.get_env(:tarearbol, :errand_options, @default_opts)

  @spec run_in_opts(Keyword.t) :: Keyword.t
  defp run_in_opts(opts), do: Keyword.delete(opts, :repeatedly)
end
