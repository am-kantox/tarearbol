defmodule Tarearbol.Crontab do
  @moduledoc false

  # minute hour day/month month day/week
  # *	any value
  # ,	value list separator
  # -	range of values
  # /	step values

  @spec next_run(input :: binary()) :: DateTime.t()
  @doc """
  Calculates the `DateTime` instance based on cron string.

  _Examples:_

      iex> Tarearbol.Crontab.next_run("*/5 * * * *")
      %{dm: "*", dw: "*", hour: "*", m: "*", min: "*/5"}

  """

  def next_run("@yearly"),
    do: Tarearbol.Calendar.beginning_of(DateTime.utc_now(), 1, :year)

  def next_run("@monthly"),
    do: Tarearbol.Calendar.beginning_of(DateTime.utc_now(), 1, :month)

  def next_run("@weekly"),
    do: Tarearbol.Calendar.beginning_of(DateTime.utc_now(), 1, :week)

  def next_run("@daily"),
    do: Tarearbol.Calendar.beginning_of(DateTime.utc_now(), 1, :day)

  def next_run("@hourly"),
    do: Tarearbol.Calendar.beginning_of(DateTime.utc_now(), 1, :hour)

  def next_run("@reboot"), do: raise("Not supported")

  def next_run("@annually"), do: raise("Not supported")

  def next_run(input) when is_binary(input),
    do: do_next_run(input, {[:hour, :dm, :m, :dw], :min, "", %{}})

  defp do_next_run("", {[], frac, acc, result}),
    do: Map.put(result, frac, acc)

  defp do_next_run(" " <> rest, {fracs, frac, acc, result}) do
    result = Map.put(result, frac, acc)
    [frac | fracs] = fracs
    do_next_run(rest, {fracs, frac, "", result})
  end

  defp do_next_run(<<c::binary-size(1), rest::binary>>, {fracs, frac, acc, result}),
    do: do_next_run(rest, {fracs, frac, acc <> c, result})
end
