defmodule Tarearbol.Utils do
  @moduledoc false

  def interval(input, opts \\ []) do
    case input do
      msec when is_integer(msec) -> msec
      sec when is_float(sec) -> round(1_000 * sec)
      :tiny -> 10
      :medium -> 100
      :regular -> 1_000
      :timeout -> 5_000
      :infinity -> opts[:value] || -1
      :random -> :rand.uniform((opts[:value] || 5_000) + 1) - 1
      _ -> 0
    end
  end

  def cron_to_time(at) when is_binary(at), do: raise "NYI: #{inspect at}"

end
