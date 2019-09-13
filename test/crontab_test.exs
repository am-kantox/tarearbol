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
