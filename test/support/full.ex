defmodule Tarearbol.Full do
  @moduledoc false
  use Tarearbol.Pool, init: &Tarearbol.Full.continue/0, pool_size: 2

  def continue, do: 0

  defsynch synch do
    {:replace, payload!() + 1}
  end

  defsynch synch(n) do
    {:replace, payload!() + n}
  end

  defasynch asynch do
    Process.sleep(500)
    {:ok, id!()}
  end

  defasynch asynch(n) do
    {:replace, payload!() + n}
  end
end
