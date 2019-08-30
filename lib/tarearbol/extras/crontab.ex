defmodule Tarearbol.Crontab do
  @moduledoc false

  @type t :: %__MODULE__{}
  defstruct [:minute, :hour, :day, :month, :day_of_week]

  @spec parse(input :: binary()) :: Tarearbol.Crontab.t()
  @doc """
  Parses the cron string into human-readable representation.

  Format: ["minute hour day/month month day/week"](https://crontab.guru/).

  _Examples:_

      iex> Tarearbol.Crontab.parse("*/5 * * * *")
      %Tarearbol.Crontab{hour: "*", day: "*", day_of_week: "*", minute: "*/5", month: "*"}

  """

  def parse("@yearly"), do: parse("0 0 1 1 *")

  def parse("@monthly"), do: parse("0 0 1 * *")

  def parse("@weekly"), do: parse("0 0 * * 1")

  def parse("@daily"), do: parse("0 0 * * *")

  def parse("@hourly"), do: parse("0 * * * *")

  def parse("@reboot"), do: raise("Not supported")

  def parse("@annually"), do: raise("Not supported")

  def parse(input) when is_binary(input),
    do: do_parse(input, {[:hour, :day, :month, :day_of_week], :minute, "", %{}})

  #############################################################################

  @spec do_parse(input :: binary(), {list[atom()], atom(), binary(), map()}) ::
          Tarearbol.Crontab.t()
  defp do_parse("", {[], frac, acc, result}),
    do: struct(Tarearbol.Crontab, Map.put(result, frac, acc))

  defp do_parse(" " <> rest, {fracs, frac, acc, result}) do
    result = Map.put(result, frac, acc)
    [frac | fracs] = fracs
    do_parse(rest, {fracs, frac, "", result})
  end

  defp do_parse(<<c::binary-size(1), rest::binary>>, {fracs, frac, acc, result}),
    do: do_parse(rest, {fracs, frac, acc <> c, result})

  #############################################################################

  # *	any value
  # ,	value list separator
  # -	range of values
  # /	step values
  @spec cron_string_to_list(
          dt :: DateTime.t(),
          {:minute | :hour | :day | :month | :day_of_week, binary()}
        ) :: Tarearbol.Crontab.t()
  defp cron_string_to_list(dt \\ nil, {:minute, input}) do
  end

  @spec parts(input :: binary()) :: [binary()]
  defp parts(input) do
    input
    |> String.split(",")
    |> Enum.flat_map(fn e ->
      case String.split(e, "/") do
        ["*", t] when byte_size(t) in [1, 2] ->
          case Integer.parse(t) do
            {int, ""} -> Stream.iterate(0, &(&1 + int))
            _ -> :error
          end

        [s, t] when byte_size(s) in [1, 2] and byte_size(t) in [1, 2] ->
          case {Integer.parse(s), Integer.parse(t)} do
            {{from, ""}, {int, ""}} -> Stream.iterate(from, &(&1 + int))
            _ -> :error
          end

        [t] when byte_size(t) in [1, 2] ->
          case Integer.parse(t) do
            {int, ""} -> Stream.iterate(0, &(&1 + int))
            _ -> :error
          end

        _ ->
          :error
      end
    end)
  end
end
