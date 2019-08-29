defmodule Tarearbol.Calendar do
  @moduledoc """
  Handy functions to work with dates.
  """

  @days_in_week 7

  @doc """
  Returns a `DateTime` instance of the beginning of the period given as third
  parameters, related to the `DateTime` instance given as the first parameter
  (defaulted to `DateTime.utc_now/0`).

  The number of periods to shift might be given as the second parameter
  (defaults to `0`.)

  _Examples:_

      iex> dt = DateTime.from_unix!(1567091960)
      ~U[2019-08-29 15:19:20Z]
      iex> Tarearbol.Calendar.beginning_of(dt, :year)
      ~U[2019-01-01 00:00:00Z]
      iex> Tarearbol.Calendar.beginning_of(dt, -2, :year)
      ~U[2017-01-01 00:00:00Z]
      iex> Tarearbol.Calendar.beginning_of(dt, :month)
      ~U[2019-08-01 00:00:00Z]
      iex> Tarearbol.Calendar.beginning_of(dt, 6, :month)
      ~U[2020-02-01 00:00:00Z]
      iex> Tarearbol.Calendar.beginning_of(dt, 4, :day)
      ~U[2019-09-02 00:00:00Z]
      iex> Tarearbol.Calendar.beginning_of(dt, :week)
      ~U[2019-08-26 00:00:00Z]
      iex> Tarearbol.Calendar.beginning_of(dt, -34, :week)
      ~U[2018-12-31 00:00:00Z]
      iex> Tarearbol.Calendar.beginning_of(dt, :hour)
      ~U[2019-08-29 15:00:00Z]
      iex> Tarearbol.Calendar.beginning_of(dt, -28*24-16, :hour)
      ~U[2019-07-31 23:00:00Z]
      iex> Tarearbol.Calendar.end_of(dt, :hour)
      ~U[2019-08-29 15:59:59Z]
      iex> Tarearbol.Calendar.end_of(dt, 5, :month)
      ~U[2020-01-31 23:59:59Z]
      iex> Tarearbol.Calendar.end_of(dt, -1, :year)
      ~U[2018-12-31 23:59:59Z]

  """
  @spec beginning_of(dt :: DateTime.t(), count :: integer(), atom()) :: DateTime.t()
  def beginning_of(dt \\ nil, count \\ 0, what)

  ###################################  YEAR  ###################################

  def beginning_of(dt, count, :year) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt

    %DateTime{nullify(dt) | year: dt.year + count, month: 1, day: 1}
  end

  ###################################  MONTH  ##################################

  def beginning_of(dt, 0, :month) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt

    %DateTime{nullify(dt) | year: dt.year, month: dt.month, day: 1}
  end

  def beginning_of(dt, 1, :month) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt

    {year, month} =
      if dt.month == dt.calendar.months_in_year(dt.year),
        do: {dt.year + 1, 1},
        else: {dt.year, dt.month + 1}

    %DateTime{nullify(dt) | year: year, month: month, day: 1}
  end

  def beginning_of(dt, -1, :month) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt

    {year, month} =
      if dt.month == 1,
        do: {dt.year - 1, dt.calendar.months_in_year(dt.year - 1)},
        else: {dt.year, dt.month - 1}

    %DateTime{nullify(dt) | year: year, month: month, day: 1}
  end

  ###################################  WEEK  ###################################

  def beginning_of(dt, 0, :week) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt
    beginning_of(dt, 1 - dt.calendar.day_of_week(dt.year, dt.month, dt.day), :day)
  end

  def beginning_of(dt, n, :week) when is_integer(n) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt

    dt
    |> beginning_of(0, :week)
    |> beginning_of(n * @days_in_week, :day)
  end

  ###################################  DAY  ####################################

  def beginning_of(dt, 0, :day) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt
    %DateTime{nullify(dt) | year: dt.year, month: dt.month, day: dt.day}
  end

  def beginning_of(dt, 1, :day) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt

    days_in_this_month = dt.calendar.days_in_month(dt.year, dt.month)
    months_in_this_year = dt.calendar.months_in_year(dt.year)

    {year, month, day} =
      case {dt.day, dt.month} do
        {^days_in_this_month, ^months_in_this_year} ->
          {dt.year + 1, 1, 1}

        {^days_in_this_month, month} ->
          {dt.year, month + 1, 1}

        {day, month} ->
          {dt.year, month, day + 1}
      end

    %DateTime{nullify(dt) | year: year, month: month, day: day}
  end

  def beginning_of(dt, -1, :day) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt

    {year, month, day} =
      case {dt.day, dt.month} do
        {1, 1} ->
          month = dt.calendar.months_in_year(dt.year - 1)
          {dt.year - 1, month, dt.calendar.days_in_month(dt.year, month)}

        {1, month} ->
          {dt.year, month - 1, dt.calendar.days_in_month(dt.year, month - 1)}

        {day, month} ->
          {dt.year, month, day - 1}
      end

    %DateTime{nullify(dt) | year: year, month: month, day: day}
  end

  ###################################  HOUR  ###################################

  def beginning_of(dt, 0, :hour) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt
    %DateTime{nullify(dt) | year: dt.year, month: dt.month, day: dt.day, hour: dt.hour}
  end

  def beginning_of(dt, -1, :hour) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt

    {year, month, day, hour} =
      case {dt.hour, dt.day, dt.month} do
        {0, 1, 1} ->
          month = dt.calendar.months_in_year(dt.year - 1)
          {dt.year - 1, month, dt.calendar.days_in_month(dt.year, month), 23}

        {0, 1, month} ->
          {dt.year, month - 1, dt.calendar.days_in_month(dt.year, month - 1), 23}

        {0, day, month} ->
          {dt.year, month, day - 1, 23}

        {hour, day, month} ->
          {dt.year, month, day, hour - 1}
      end

    %DateTime{nullify(dt) | year: year, month: month, day: day, hour: hour}
  end

  def beginning_of(dt, 1, :hour) do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt

    days_in_this_month = dt.calendar.days_in_month(dt.year, dt.month)
    months_in_this_year = dt.calendar.months_in_year(dt.year)

    {year, month, day, hour} =
      case {dt.hour, dt.day, dt.month} do
        {23, ^days_in_this_month, ^months_in_this_year} ->
          {dt.year + 1, 1, 1, 0}

        {23, ^days_in_this_month, month} ->
          {dt.year, month + 1, 1, 0}

        {23, day, month} ->
          {dt.year, month, day + 1, 0}

        {hour, day, month} ->
          {dt.year, month, day, hour + 1}
      end

    %DateTime{nullify(dt) | year: year, month: month, day: day, hour: hour}
  end

  ##################################  GENERICS  ################################

  def beginning_of(dt, count, period) when count > 1 do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt
    Enum.reduce(1..count, dt, fn _, acc -> beginning_of(acc, 1, period) end)
  end

  def beginning_of(dt, count, period) when count < 1 do
    dt = if is_nil(dt), do: DateTime.utc_now(), else: dt
    Enum.reduce(1..-count, dt, fn _, acc -> beginning_of(acc, -1, period) end)
  end

  ###################################  END_OF  #################################

  @spec end_of(dt :: DateTime.t(), count :: integer(), atom()) :: DateTime.t()
  def end_of(dt \\ nil, n \\ 0, period)

  def end_of(dt, n, period) do
    dt
    |> beginning_of(n, period)
    |> DateTime.add(period_in_seconds(dt, period) - 1)
  end

  ##################################  INTERNALS  ###############################

  defp period_in_seconds(dt \\ nil, period)

  defp period_in_seconds(_, :minute), do: 60
  defp period_in_seconds(_, :hour), do: 60 * 60
  defp period_in_seconds(_, :day), do: 60 * 60 * 24

  defp period_in_seconds(dt, :month),
    do: dt.calendar.days_in_month(dt.year, dt.month) * period_in_seconds(:day)

  defp period_in_seconds(dt, :year) do
    Enum.reduce(1..dt.calendar.months_in_year(dt.year), 0, fn month, acc ->
      acc + dt.calendar.days_in_month(dt.year, month) * period_in_seconds(:day)
    end)
  end

  defp nullify(%DateTime{} = dt) do
    %DateTime{
      dt
      | year: 0,
        month: 0,
        day: 0,
        hour: 0,
        minute: 0,
        second: 0,
        microsecond: {0, 0}
    }
  end
end
