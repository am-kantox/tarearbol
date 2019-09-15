defmodule Tarearbol.Crontab.Test do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol.Crontab
  doctest Tarearbol.Calendar

  test "both greedy and lazy methods return the same" do
    dt = DateTime.utc_now()
    greedy = Tarearbol.Crontab.next_as_list(dt, "42 * 30 8 6,7", precision: :microsecond)
    lazy = Tarearbol.Crontab.next_as_stream(dt, "42 * 30 8 6,7", precision: :microsecond)

    assert greedy[:next] ==
             Enum.map(lazy, &[{:timestamp, &1[:next]}, {:microsecond, &1[:microsecond]}])
  end

  test "DOM and DOW are OR-ed" do
    # ~U[2019-08-29 15:19:20Z]
    dt = DateTime.from_unix!(1_567_091_960)
    record = "42 3 31 8 5"

    greedy =
      Tarearbol.Crontab.next_as_list(dt, record)[:next]
      |> Enum.take(2)
      |> Enum.map(& &1[:timestamp])

    lazy =
      dt
      |> Tarearbol.Crontab.next_as_stream(record)
      |> Enum.take(2)
      |> Enum.map(& &1[:next])

    assert greedy ==
             [~U[2019-08-30 03:42:00Z], ~U[2019-08-31 03:42:00Z]]

    assert lazy ==
             [~U[2019-08-30 03:42:00Z], ~U[2019-08-31 03:42:00Z]]
  end
end
