defmodule Tarearbol.Crontab.Bench do
  use Benchfella

  @dt DateTime.utc_now()

  bench "list" do
    1..1_000
    |> Enum.map(fn _ ->
      Tarearbol.Crontab.next_as_list(@dt, "42 * 30 8 6,7", precision: :microsecond)
    end)
  end

  bench "stream_am" do
    1..1_000
    |> Enum.map(fn _ ->
      Tarearbol.Crontab.next_as_stream_am(@dt, "42 * 30 8 6,7", precision: :microsecond)
    end)
  end

  bench "stream_st" do
    1..1_000
    |> Enum.map(fn _ ->
      Tarearbol.Crontab.next_as_stream_st(@dt, "42 * 30 8 6,7", precision: :microsecond)
    end)
  end
end
