defmodule Tarearbol.Errand do
  @moduledoc false

  require Logger

  @default_opts [
    repeatedly: false
  ]

  def run_in(job, interval, opts \\ []) do
    Tarearbol.Application.task!(fn ->
      Process.sleep(Tarearbol.Utils.interval(interval, value: 0))
      Tarearbol.Job.ensure(job, opts)
    end)
  end

  def run_at(job, at, opts \\ [])
  def run_at(job, %DateTime{} = at, opts), do: raise "NYI: #{inspect {job, at, opts}}"
  def run_at(job, at, opts) when is_binary(at),
    do: run_at(job, Tarearbol.Utils.cron_to_time(at), opts)

  def spawn(job, opts \\ []), do: run_in(job, 0, opts)

  def opts, do: Application.get_env(:tarearbol, :errand_options, @default_opts)
end
