defmodule Tarearbol.Crontab do
  @moduledoc """
  Helper functions to work with `cron` syntax.
  """

  @typedoc "Internal representation of the record in cron file"
  @type t :: %__MODULE__{}
  defstruct [:minute, :hour, :day, :month, :day_of_week]

  @prefix ""

  @doc """
  Returns the next `DateTime` the respective `cron` record points to
  with a precision given as the third argument (default: `:second`.)

  If the first parameter is not given, it assumes _the next after now_.

  _Examples_

      iex> dt = DateTime.from_unix!(1567091960)
      ~U[2019-08-29 15:19:20Z]
      iex> Tarearbol.Crontab.next(dt, "42 3 28 08 *")
      [
        origin: ~U[2019-08-29 15:19:20Z],
        next: ~U[2020-08-28 03:42:00Z],
        second: 31494160
      ]

  where `origin` contains the timestamp to lookup the `next` for, `next`
  is the `DateTime` instance of the next event and `second` is the
  {`precision`, `difference_in_that_precision`}.
  """
  @spec next(dt :: nil | DateTime.t(), input :: binary(), opts :: keyword()) :: DateTime.t()
  def next(dt \\ nil, input, opts \\ [])

  def next(nil, input, opts), do: next(DateTime.utc_now(), input, opts)

  def next(%DateTime{} = dt, input, opts),
    do: dt |> next_as_stream(input, opts) |> Enum.take(1) |> hd()

  @doc """
  Returns the _list_ of all the events after `dt` (default: `DateTime.utc_now/0`.)

  This function calculates the outcome greedily and, while it might be slightly
  faster than `Tarearbol.Crontab.next_as_stream/3`, it should not be used for
  frequently recurring cron records (like `"* * * * *"`.)
  """
  @spec next_as_list(dt :: nil | DateTime.t(), input :: binary(), opts :: keyword()) ::
          keyword()
  def next_as_list(dt \\ nil, input, opts \\ [])

  def next_as_list(nil, input, opts),
    do: next_as_list(DateTime.utc_now(), input, opts)

  def next_as_list(%DateTime{} = dt, input, opts) do
    precision = Keyword.get(opts, :precision, :second)

    %Tarearbol.Crontab{} = ct = prepare(input)

    next_dts =
      for year <- [dt.year, dt.year + 1],
          month <- 1..dt.calendar.months_in_year(year),
          year > dt.year || month >= dt.month,
          ct.month.eval.(month: month),
          day <- 1..dt.calendar.days_in_month(year, month),
          year > dt.year || month > dt.month || day >= dt.day,
          ct.day.eval.(day: day),
          day_of_week <- [dt.calendar.day_of_week(year, month, day)],
          ct.day_of_week.eval.(day_of_week: day_of_week),
          hour <- 0..23,
          year > dt.year || month > dt.month || day > dt.day || hour >= dt.hour,
          ct.hour.eval.(hour: hour),
          minute <- 0..59,
          year > dt.year || month > dt.month || day > dt.day || hour > dt.hour ||
            minute > dt.minute,
          ct.minute.eval.(minute: minute),
          do: %DateTime{
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: 0,
            microsecond: dt.microsecond,
            time_zone: dt.time_zone,
            zone_abbr: dt.zone_abbr,
            utc_offset: dt.utc_offset,
            std_offset: dt.std_offset,
            calendar: dt.calendar
          }

    [
      {:origin, DateTime.truncate(dt, precision)},
      {:next,
       Enum.map(next_dts, fn next_dt ->
         [
           {:timestamp, DateTime.truncate(next_dt, precision)},
           {precision, DateTime.diff(next_dt, dt, precision)}
         ]
       end)}
    ]
  end

  @doc """
  Returns the _stream_ of all the events after `dt` (default: `DateTime.utc_now/0`.)

  This function calculates the outcome lazily, returning a stream.

  See `Tarearbol.Crontab.next_as_list/3` for greedy evaluation.
  """
  @spec next_as_stream(dt :: nil | DateTime.t(), input :: binary(), opts :: keyword()) ::
          Stream.t()
  def next_as_stream(dt \\ nil, input, opts \\ [])

  def next_as_stream(nil, input, opts),
    do: next_as_stream(DateTime.utc_now(), input, opts)

  def next_as_stream(
        %DateTime{
          year: dty,
          month: dtm,
          day: dtd,
          hour: dth,
          minute: dtmin
        } = dt,
        input,
        opts
      ) do
    precision = Keyword.get(opts, :precision, :second)

    %Tarearbol.Crontab{} = ct = input |> parse() |> prepare()

    # {stream, :ok} =
    [dt.year, dt.year + 1]
    |> Stream.transform(:ok, fn year, :ok ->
      1..dt.calendar.months_in_year(year)
      |> Stream.drop_while(&match?(month when {year, month} < {dty, dtm}, &1))
      |> Stream.filter(&ct.month.eval.(month: &1))
      |> Stream.transform(:ok, fn month, :ok ->
        1..dt.calendar.days_in_month(year, month)
        |> Stream.drop_while(&match?(day when {year, month, day} < {dty, dtm, dtd}, &1))
        |> Stream.filter(&ct.day.eval.(day: &1))
        |> Stream.filter(
          &ct.day_of_week.eval.(day_of_week: dt.calendar.day_of_week(year, month, &1))
        )
        |> Stream.transform(:ok, fn day, :ok ->
          0..23
          |> Stream.drop_while(
            &match?(hour when {year, month, day, hour} < {dty, dtm, dtd, dth}, &1)
          )
          |> Stream.filter(&ct.hour.eval.(hour: &1))
          |> Stream.transform(:ok, fn hour, :ok ->
            0..59
            |> Stream.drop_while(
              &match?(
                minute when {year, month, day, hour, minute} < {dty, dtm, dtd, dth, dtmin},
                &1
              )
            )
            |> Stream.filter(&ct.minute.eval.(minute: &1))
            |> Stream.map(fn minute ->
              next_dt = %DateTime{
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: 0,
                microsecond: dt.microsecond,
                time_zone: dt.time_zone,
                zone_abbr: dt.zone_abbr,
                utc_offset: dt.utc_offset,
                std_offset: dt.std_offset,
                calendar: dt.calendar
              }

              [
                {:origin, DateTime.truncate(dt, precision)},
                {:next, DateTime.truncate(next_dt, precision)},
                {precision, DateTime.diff(next_dt, dt, precision)}
              ]
            end)
            |> (&{&1, :ok}).()
          end)
          |> (&{&1, :ok}).()
        end)
        |> (&{&1, :ok}).()
      end)
      |> (&{&1, :ok}).()
    end)

    #    stream
  end

  @doc """
  Parses the cron string into `Tarearbol.Crontab.t()` struct.

  Input format: ["minute hour day/month month day/week"](https://crontab.guru/).
  """

  @spec prepare(input :: binary() | Tarearbol.Crontab.t()) :: Tarearbol.Crontab.t()
  def prepare(input) when is_binary(input),
    do: input |> parse() |> prepare()

  def prepare(%Tarearbol.Crontab{
        minute: minute,
        hour: hour,
        day: day,
        month: month,
        day_of_week: day_of_week
      }) do
    %Tarearbol.Crontab{
      minute: Formulae.compile(minute),
      hour: Formulae.compile(hour),
      day: Formulae.compile(day),
      month: Formulae.compile(month),
      day_of_week: Formulae.compile(day_of_week)
    }
  end

  @doc """
  Parses the cron string into human-readable representation.

  **This function is exported for debugging purposes only, normally one would call `prepare/1` instead.**

  Input format: ["minute hour day/month month day/week"](https://crontab.guru/).

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

  @spec parse(input :: binary()) :: Tarearbol.Crontab.t()
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

  defp do_parse("@reboot", _acc), do: raise("Not supported")

  defp do_parse("@annually", _acc), do: raise("Not supported")

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
  defp parts(key, input) do
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

  @spec str_to_int(input :: binary(), acc :: {1 | -1, [integer()]} | {:error, any()}) ::
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

  @doc """
  Produces the single formula out of cron record. Might be useful
  for some external check that requires the single validation call.

  _Examples_

      iex> Tarearbol.Crontab.formula("42 3 28 08 *").formula
      "(day == 28) && (rem(day_of_week, 1) == 0) && (hour == 3) && (minute == 42) && (month == 8)"

      iex> Tarearbol.Crontab.formula("423 * * * *")
      {:error, [minute: {:could_not_parse_field, ["423"]}]}

  """
  @spec formula(ct :: binary() | Tarearbol.Crontab.t()) :: :error | binary()
  def formula(ct) when is_binary(ct) do
    with f when is_binary(f) <- ct |> parse() |> formula(), do: Formulae.compile(f)
  end

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

  defimpl Enumerable do
    @moduledoc false

    @doc false
    def count(%Tarearbol.Crontab{} = _sct), do: {:ok, 5}

    @doc false
    Enum.each([:minute, :hour, :day, :month, :day_of_week], fn item ->
      def member?(%Tarearbol.Crontab{} = _sct, unquote(item)), do: {:ok, true}
    end)

    def member?(%Tarearbol.Crontab{} = _sct, _val), do: false

    @doc false
    def slice(%Tarearbol.Crontab{} = _sct), do: raise("Not implemented")

    @doc false
    def reduce(%Tarearbol.Crontab{} = sct, acc, fun) do
      Enumerable.List.reduce(
        for({key, formulae} <- Map.from_struct(sct), do: {key, formulae}),
        acc,
        fun
      )
    end
  end
end
