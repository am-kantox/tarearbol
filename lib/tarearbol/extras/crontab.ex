defmodule Tarearbol.Crontab do
  @moduledoc false

  @type t :: %__MODULE__{}
  defstruct [:minute, :hour, :day, :month, :day_of_week]

  # @prefix "dt."
  @prefix ""

  @spec next(dt :: nil | DateTime.t(), input :: binary()) :: DateTime.t()
  def next(dt \\ nil, input) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt

    with %Tarearbol.Crontab{} = ct <- parse(input),
         %Tarearbol.Crontab{} = ct <- IO.inspect(quote_it(ct)) do
      started = :erlang.monotonic_time(:microsecond)

      try do
        for(
          year <- [dt.year, dt.year + 1],
          month <- 1..dt.calendar.months_in_year(year),
          year > dt.year || month >= dt.month,
          day <- 1..dt.calendar.days_in_month(year, month),
          year > dt.year || month > dt.month || day >= dt.day,
          day_of_week <- [dt.calendar.day_of_week(dt.year, dt.month, dt.day)],
          hour <- 0..23,
          year > dt.year || month > dt.month || day > dt.day || hour >= dt.hour,
          minute <- 0..59,
          year > dt.year || month > dt.month || day > dt.day || hour > dt.hour ||
            minute >= dt.minute,
          formula_check(ct.month, month: month),
          formula_check(ct.day, day: day),
          formula_check(ct.day_of_week, day_of_week: day_of_week),
          formula_check(ct.hour, hour: hour),
          formula_check(ct.minute, minute: minute),
          do:
            throw(
              IO.inspect(%DateTime{
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: 0,
                microsecond: {0, 0},
                time_zone: dt.time_zone,
                zone_abbr: dt.zone_abbr,
                utc_offset: dt.utc_offset,
                std_offset: dt.std_offset,
                calendar: dt.calendar
              })
            )
        )
      catch
        result ->
          IO.inspect(:erlang.monotonic_time(:microsecond) - started, label: "Spent in fun")
          result
      end

      # |> Stream.map(& &1)
      # |> Enum.take(1)
    end
  end

  @spec quote_it(input :: Tarearbol.Crontab.t()) :: Tarearbol.Crontab.t()
  def quote_it(%Tarearbol.Crontab{
        minute: minute,
        hour: hour,
        day: day,
        month: month,
        day_of_week: day_of_week
      }) do
    %Tarearbol.Crontab{
      minute: Code.string_to_quoted(minute),
      hour: Code.string_to_quoted(hour),
      day: Code.string_to_quoted(day),
      month: Code.string_to_quoted(month),
      day_of_week: Code.string_to_quoted(day_of_week)
    }
  end

  @spec parse(input :: binary()) :: Tarearbol.Crontab.t()
  @doc """
  Parses the cron string into human-readable representation.

  Format: ["minute hour day/month month day/week"](https://crontab.guru/).

  _Examples:_

      iex> Tarearbol.Crontab.parse "10-30/5 */4 1 */1 6,7"
      %Tarearbol.Crontab{
        day: "(day == 1)",
        day_of_week: "(day_of_week == 6 || day_of_week == 7)",
        hour: "(rem(hour, 4) == 0)",
        minute: "(rem(minute, 5) == 0 && minute >= 10 && minute <= 30)",
        month: "(rem(month, 1) == 0)"
      }

  _In case of malformed input:_

      iex> Tarearbol.Crontab.parse "10-30/5 */4 1 */1 6d,7"
      %Tarearbol.Crontab{
        day: "(day == 1)",
        day_of_week: {:error, {:could_not_parse_integer, "6d"}},
        hour: "(rem(hour, 4) == 0)",
        minute: "(rem(minute, 5) == 0 && minute >= 10 && minute <= 30)",
        month: "(rem(month, 1) == 0)"
      }

  """

  def parse(input) when is_binary(input),
    do: do_parse(input, {[:hour, :day, :month, :day_of_week], :minute, "", %{}})

  #############################################################################

  @spec do_parse(input :: binary(), {list[atom()], atom(), binary(), map()}) ::
          Tarearbol.Crontab.t()

  defp do_parse("@yearly", acc), do: do_parse("0 0 1 1 *", acc)

  defp do_parse("@monthly", acc), do: do_parse("0 0 1 * *", acc)

  defp do_parse("@weekly", acc), do: do_parse("0 0 * * 1", acc)

  defp do_parse("@daily", acc), do: do_parse("0 0 * * *", acc)

  defp do_parse("@hourly", acc), do: do_parse("0 * * * *", acc)

  defp do_parse("@reboot", acc), do: raise("Not supported")

  defp do_parse("@annually", acc), do: raise("Not supported")

  defp do_parse("", {[], frac, acc, result}) do
    map = for {k, v} <- Map.put(result, frac, acc), into: %{}, do: {k, parts(k, v)}
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

  @spec parts(key :: atom(), input :: binary()) :: [binary()]
  def parts(key, input) do
    input
    |> String.split(",")
    |> Enum.reduce({:ok, []}, fn e, acc ->
      case {acc, String.split(e, "/")} do
        {{:error, reason}, _} ->
          {:error, reason}

        {{:ok, acc}, ["*"]} ->
          with {:ok, result} <- parse_int(key, "1"), do: {:ok, [result | acc]}

        {{:ok, acc}, ["*", t]} when is_cc(t) ->
          with {:ok, result} <- parse_int(key, t), do: {:ok, [result | acc]}

        {{:ok, acc}, [s, t]} when is_cc(s) and is_cc(t) ->
          with {:ok, result} <- parse_int(key, s, t), do: {:ok, [result | acc]}

        {{:ok, acc}, [<<s1::binary-size(1), "-", s2::binary>>, t]} when is_cc(t) ->
          with {:ok, result} <- parse_int(key, s1, s2, t), do: {:ok, [result | acc]}

        {{:ok, acc}, [<<s1::binary-size(2), "-", s2::binary>>, t]} when is_cc(t) ->
          with {:ok, result} <- parse_int(key, s1, s2, t), do: {:ok, [result | acc]}

        {{:ok, acc}, [<<s1::binary-size(1), "-", s2::binary>>]} ->
          with {:ok, result} <- parse_int(key, s1, s2, "1"), do: {:ok, [result | acc]}

        {{:ok, acc}, [<<s1::binary-size(2), "-", s2::binary>>]} ->
          with {:ok, result} <- parse_int(key, s1, s2, "1"), do: {:ok, [result | acc]}

        {{:ok, acc}, [s]} when is_cc(s) ->
          case Integer.parse(s) do
            {int, ""} -> {:ok, ["#{@prefix}#{key} == #{int}" | acc]}
            _ -> {:error, {:could_not_parse_integer, s}}
          end

        {{:ok, _}, unknown} ->
          {:error, {:could_not_parse_field, unknown}}
      end
    end)
    |> case do
      {:ok, acc} ->
        result =
          acc
          |> Enum.reverse()
          |> Enum.join(" || ")

        "(" <> result <> ")"

      other ->
        other
    end
  end

  @spec parse_int(key :: atom(), s :: binary()) :: binary() | {:error, any()}
  defp parse_int(key, s) do
    case str_to_int(s) do
      {:error, reason} -> {:error, reason}
      int -> {:ok, "rem(#{@prefix}#{key}, #{int}) == 0"}
    end
  end

  @spec parse_int(key :: atom(), s1 :: binary(), s2 :: binary()) :: binary() | {:error, any()}
  defp parse_int(key, s1, s2) do
    case {str_to_int(s1), str_to_int(s2)} do
      {{:error, r1}, {:error, r2}} -> {:error, [r1, r2]}
      {{:error, r1}, _} -> {:error, r1}
      {_, {:error, r2}} -> {:error, r2}
      {from, int} -> {:ok, "rem(#{@prefix}#{key}, #{int}) == 0 && #{@prefix}#{key} >= #{from}"}
    end
  end

  @spec parse_int(key :: atom(), s1 :: binary(), s2 :: binary(), s :: binary()) ::
          binary() | {:error, any()}
  defp parse_int(key, s1, s2, s) do
    case {str_to_int(s1), str_to_int(s2), str_to_int(s)} do
      {{:error, r1}, {:error, r2}, {:error, r3}} ->
        {:error, [r1, r2, r3]}

      {{:error, r1}, {:error, r2}, _} ->
        {:error, [r1, r2]}

      {{:error, r1}, _, {:error, r3}} ->
        {:error, [r1, r3]}

      {_, {:error, r2}, {:error, r3}} ->
        {:error, [r2, r3]}

      {{:error, r1}, _, _} ->
        {:error, r1}

      {_, {:error, r2}, _} ->
        {:error, r2}

      {_, _, {:error, r3}} ->
        {:error, r3}

      {from, till, int} ->
        {:ok,
         "rem(#{@prefix}#{key}, #{int}) == 0 && #{@prefix}#{key} >= #{from} && #{@prefix}#{key} <= #{
           till
         }"}
    end
  end

  @spec str_to_int(input :: binary(), acc :: {1 | -1, [integer()]}) ::
          integer() | {:error, any()}
  defp str_to_int(input, acc \\ {1, []})
  defp str_to_int(_, {:error, reason}), do: {:error, reason}

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

  defp str_to_int(input, _), do: {:error, {:could_not_parse_integer, input}}

  ##############################################################################

  @spec formula(ct :: Tarearbol.Crontab.t()) :: :error | binary()
  def formula(%Tarearbol.Crontab{} = ct) do
    ct
    |> Enum.reduce({:ok, []}, fn
      {key, {:error, reason}}, {:ok, _} -> {:error, [{key, reason}]}
      {key, {:error, reason}}, {:error, reasons} -> {:error, [{key, reason} | reasons]}
      {_key, _formulae}, {:error, reasons} -> {:error, reasons}
      {_key, formulae}, {:ok, result} -> {:ok, [formulae | result]}
    end)
    |> case do
      {:error, reasons} -> {:error, reasons}
      {:ok, result} -> result |> Enum.reverse() |> Enum.join(" && ")
    end
  end

  @spec date_time_with_day_of_week(dt :: nil | DateTime.t()) :: map()
  defp date_time_with_day_of_week(dt \\ nil) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt

    dt
    |> Map.from_struct()
    |> Map.put_new(:day_of_week, dt.calendar.day_of_week(dt.year, dt.month, dt.day))
  end

  @spec formula_check(formula :: binary(), binding :: keyword()) :: boolean()
  defp formula_check(formula, binding) do
    # started = :erlang.monotonic_time(:microsecond)

    case Code.eval_quoted(formula, binding, []) do
      {{:ok, false}, _} -> false
      {{:ok, true}, _} -> true
    end

    # IO.inspect(:erlang.monotonic_time(:microsecond) - started, label: inspect(binding))
    # result
  end

  defimpl Enumerable do
    def count(%Tarearbol.Crontab{} = _sct), do: 5

    Enum.each([:minute, :hour, :day, :month, :day_of_week], fn item ->
      def member?(%Tarearbol.Crontab{} = _sct, unquote(item)), do: true
    end)

    def member?(%Tarearbol.Crontab{} = _sct, _val), do: false

    def slice(%Tarearbol.Crontab{} = _sct), do: raise("Not implemented")

    def reduce(%Tarearbol.Crontab{} = sct, acc, fun) do
      Enumerable.List.reduce(
        for({key, formulae} <- Map.from_struct(sct), do: {key, formulae}),
        acc,
        fun
      )
    end
  end
end
