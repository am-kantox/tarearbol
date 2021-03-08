defmodule Tarearbol.Full do
  @moduledoc false
  use Tarearbol.Pool, continue: {Tarearbol.Full, :continue, 0}

  def continue do
    0
  end

  defsynch foo() do
    {:replace, payload!() + 1}
  end

  defasynch bar() do
    Process.sleep(10_000)
    IO.puts(:bar_casted)
  end
end
