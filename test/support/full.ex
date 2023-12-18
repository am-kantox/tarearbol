defmodule Tarearbol.Full do
  @moduledoc false
  use Tarearbol.Pool,
    init: &Tarearbol.Full.continue/0,
    pool_size: 2,
    pickup: :random,
    defaults: [timeout: 0]

  def continue, do: 0

  defsynch synch(n \\ 1)

  defsynch synch(n) do
    {:replace, payload!() + n}
  end

  defsynch synch(n, %{} = _map) do
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
