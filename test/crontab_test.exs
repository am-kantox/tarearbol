defmodule Tarearbol.Crontab.Test do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol.Crontab
  doctest Tarearbol.Calendar

  test "both greedy and lazy methods return the same" do
    dt = DateTime.utc_now()
    greedy = Tarearbol.Crontab.next_as_list(dt, "42 * 30 8 6,7", precision: :microsecond)
    lazy_am = Tarearbol.Crontab.next_as_stream_am(dt, "42 * 30 8 6,7", precision: :microsecond)
    lazy_st = Tarearbol.Crontab.next_as_stream_st(dt, "42 * 30 8 6,7", precision: :microsecond)

    assert greedy[:next] ==
             Enum.map(lazy_am, &[{:timestamp, &1[:next]}, {:microsecond, &1[:microsecond]}])

    assert greedy[:next] ==
             Enum.map(lazy_st, &[{:timestamp, &1[:next]}, {:microsecond, &1[:microsecond]}])
  end
end
