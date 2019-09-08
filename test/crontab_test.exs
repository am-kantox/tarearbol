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
end
