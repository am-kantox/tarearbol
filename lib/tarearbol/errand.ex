defmodule Tarearbol.Errand do
  @moduledoc false

  require Logger

  @default_opts [
    repeatedly: false
  ]

  @doc "`:repeatedly` parameter will discard `on_success` handler if presented"
  def run_in(job, interval, opts \\ opts()) do
    Tarearbol.Application.task!(fn ->
      Process.put(:job, {job, opts, Tarearbol.Utils.add_interval(interval)})
      Process.sleep(Tarearbol.Utils.interval(interval, value: 0))
      ensure_opts =
        case Keyword.fetch(opts, :repeatedly) do
          {:ok, true} ->
            opts
            |> Keyword.delete(:repeatedly)
            |> Keyword.put(:on_success, fn -> Tarearbol.Errand.run_in(job, interval, opts) end)
          _ -> opts
        end
      Tarearbol.Job.ensure(job, ensure_opts)
    end)
  end

  def run_at(job, at, opts \\ opts())
  def run_at(job, %DateTime{} = at, opts),
    do: run_in(job, DateTime.diff(at, DateTime.utc_now, :millisecond), opts)
  def run_at(job, %Time{} = at, opts) do
    run_in = case Time.diff(at, Time.utc_now, :millisecond) do
               msec when msec <= 0 ->
                 msec + 1_000 * 60 * 60 * 24 # tomorrow at that time
               msec -> msec
             end
    run_in(job, run_in, Keyword.put(opts, :on_success, fn -> Tarearbol.Errand.run_at(job, at, opts) end))
  end
  def run_at(job, at, opts) when is_binary(at),
    do: run_at(job, Tarearbol.Utils.cron_to_time(at), opts)

  def spawn(job, opts \\ opts()), do: run_in(job, 0, opts)

  def opts, do: Application.get_env(:tarearbol, :errand_options, @default_opts)
end
