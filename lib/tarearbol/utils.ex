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

  def add_interval(input, to \\ nil) do
    (((to || DateTime.utc_now) |> DateTime.to_unix(:milliseconds)) + interval(input))
    |> DateTime.from_unix!(:milliseconds)
  end

  def cron_to_time(at) when is_binary(at), do: raise "NYI: #{inspect at}"

  # defp decronify(<<"*/" :: binary, rest :: binary>>, min, max) do
  defp decronify(<<"*/" :: binary, rest :: binary>>, min, max) do
    every = String.to_integer(rest)
    "*"
    |> decronify(min, max)
    |> Enum.with_index
    |> Enum.filter(fn {_, idx} -> Integer.mod(idx, every) == 0 end)
    |> Enum.map(fn {value, _} -> value end)
  end
  defp decronify("*", min, max), do: Enum.to_list(min..max)

end
