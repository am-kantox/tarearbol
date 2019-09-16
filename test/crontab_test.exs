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

  test "step on range" do
    {:ok, dt, _} = DateTime.from_iso8601("2019-06-10T00:00:00Z")
    {:ok, nxt, _} = DateTime.from_iso8601("2019-06-10T00:03:00Z")
    cron = "3-9/2 * * * *"
    assert nxt == Tarearbol.Crontab.next(dt, cron) |> Keyword.get(:next)
  end

  test "day of week and month+day are not co-dependent" do
    {:ok, dt, _} = DateTime.from_iso8601("2019-06-10T00:00:00Z")
    {:ok, nxt, _} = DateTime.from_iso8601("2019-06-12T00:00:00Z")
    {:ok, nxt2, _} = DateTime.from_iso8601("2019-06-17T00:00:00Z")
    cron = "0 0 12 6 1"
    assert nxt == Tarearbol.Crontab.next(%{dt | minute: 1}, cron) |> Keyword.get(:next)
    assert nxt2 == Tarearbol.Crontab.next(%{nxt | minute: 1}, cron) |> Keyword.get(:next)
  end
end
