defmodule Tarearbol.Crontab do
  @moduledoc false

  @type t :: %__MODULE__{}
  defstruct [:minute, :hour, :day, :month, :day_of_week]

  @spec next(dt :: nil | DateTime.t(), input :: binary()) :: DateTime.t()
  def next(dt \\ nil, input) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt

    #     scheduled = %{
    #       month: dt.month,
    #       day: dt.day,
    #       hour: dt.hour,
    #       minute: dt.minute,
    #       day_of_week: dt.calendar.day_of_week(dt.year, dt.month, dt.day)
    #     }
    # Tarearbol.Calendar.beginning_of(dt, count, :minute)
    #     with %Tarearbol.Crontab{} = ct <- parse(input) do
    #       Stream.map(ct, fn {k, s} ->
    #         s
    #         |> Stream.drop_while(&(&1 < scheduled[k]))
    #         |> Stream.take(1)
    #         |> case do
    #           [] -> Enum.take(enumerable, amount)
    #         end
    #       end)
    #     end
  end

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
  defp do_parse("", {[], frac, acc, result}) do
    map = for {k, v} <- Map.put(result, frac, acc), into: %{}, do: {k, parts(v)}
    struct(Tarearbol.Crontab, map)
  end

  defp do_parse(" " <> rest, {fracs, frac, acc, result}) do
    result = Map.put(result, frac, acc)
    [frac | fracs] = fracs
    do_parse(rest, {fracs, frac, "", result})
  end

  defp do_parse(<<c::binary-size(1), rest::binary>>, {fracs, frac, acc, result}),
    do: do_parse(rest, {fracs, frac, acc <> c, result})

  #############################################################################

  # defguardp is_digit(c) when c in ?0..?9
  defguardp is_cc(cc) when byte_size(cc) in [1, 2]

  @spec parts(input :: binary()) :: [Enumerable.t()]
  def parts(input) do
    input
    |> String.split(",")
    |> Enum.map(fn e ->
      case String.split(e, "/") do
        ["*"] ->
          parse_int("1")

        ["*", t] when is_cc(t) ->
          parse_int(t)

        [s, t] when is_cc(s) and is_cc(t) ->
          parse_int(s, t)

        [<<s1::binary-size(1), "-", s2::binary>>, t] when is_cc(t) ->
          parse_int(s1, s2, t)

        [<<s1::binary-size(2), "-", s2::binary>>, t] when is_cc(t) ->
          parse_int(s1, s2, t)

        [s] when is_cc(s) ->
          case Integer.parse(s) do
            {int, ""} -> Stream.map([int], & &1)
            _ -> :error
          end

        _ ->
          :error
      end
    end)
  end

  @spec parse_int(s :: binary()) :: Enumerable.t() | :error
  defp parse_int(s) do
    with int when int != :error <- str_to_int(s),
         do: Stream.iterate(0, &(&1 + int))
  end

  @spec parse_int(s1 :: binary(), s2 :: binary()) :: Enumerable.t() | :error
  defp parse_int(s1, s2) do
    with from when from != :error <- str_to_int(s1),
         int when int != :error <- str_to_int(s2),
         do: Stream.iterate(from, &(&1 + int))
  end

  @spec parse_int(s1 :: binary(), s2 :: binary(), s :: binary()) :: Enumerable.t() | :error
  defp parse_int(s1, s2, s) do
    with int when int != :error <- str_to_int(s2),
         stream when stream != :error <- parse_int(s1, s),
         do: Stream.take_while(stream, &(&1 < int))
  end

  @spec str_to_int(input :: binary(), acc :: {1 | -1, [integer()]}) :: integer() | :error
  defp str_to_int(input, acc \\ {1, []})
  defp str_to_int(_, :error), do: :error

  defp str_to_int(<<"+", rest::binary>>, {_, []}), do: str_to_int(rest, {1, []})
  defp str_to_int(<<"-", rest::binary>>, {_, []}), do: str_to_int(rest, {-1, []})

  defp str_to_int("", {sign, acc}) do
    acc
    |> Enum.reduce({1, 0}, fn digit, {denom, result} ->
      {denom * 10, result + digit * denom}
    end)
    |> elem(1)
    |> Kernel.*(sign)
  end

  defp str_to_int(<<c::8, rest::binary>>, {sign, acc}) when c in ?0..?9,
    do: str_to_int(rest, {sign, [c - 48 | acc]})

  defp str_to_int(_, _), do: :error

  defimpl Enumerable do
    def count(%Tarearbol.Crontab{} = sct),
      do: {:ok, Enum.reduce(Map.from_struct(sct), 0, fn {_, s} -> Enum.count(s) end)}

    def member?(%Tarearbol.Crontab{} = _sct, _val), do: raise("Not implemented")
    def slice(%Tarearbol.Crontab{} = _sct), do: raise("Not implemented")

    def reduce(%Tarearbol.Crontab{} = sct, acc, fun) do
      Enumerable.List.reduce(
        for({k, list} <- Map.from_struct(sct), s <- list, do: {k, s}),
        acc,
        fun
      )
    end
  end
end
