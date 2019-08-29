defmodule Tarearbol.Crontab do
  @moduledoc false

  # minute hour day/month month day/week
  # *	any value
  # ,	value list separator
  # -	range of values
  # /	step values

  @spec next_run(input :: binary()) :: DateTime.t()

  def next_run("@yearly"), do: Calendar.beginning_of(1, :year)

  def next_run("@monthly") do
  end

  def next_run("@weekly") do
  end

  def next_run("@daily") do
  end

  def next_run("@hourly") do
  end

  def next_run("@reboot"), do: raise("Not supported")
  def next_run("@annually"), do: raise("Not supported")

  def next_run(input) when is_binary(input), do: do_next_run(input, %{})

  defp do_next_run(input, acc) do
  end
end
