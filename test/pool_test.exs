defmodule Tarearbol.DynamicManager.Pool.Test do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol.DynamicManager

  setup do
    # with {:ok, pid} <- DynamicManager.start_link(), do: [pid: pid]
    :ok
  end

  test "acts as expected" do
    {:ok, pid} = Tarearbol.Full.start_link()

    Process.sleep(100)

    assert Tarearbol.Full.synch() == {:ok, 1}
    assert Tarearbol.Full.synch() == {:ok, 2}
    assert Tarearbol.Full.synch(3) == {:ok, 5}

    assert Tarearbol.Full.asynch() == :ok
    Process.sleep(10)
    assert Tarearbol.Full.asynch() == :ok
    Process.sleep(10)
    assert Tarearbol.Full.asynch() == :error
    Process.sleep(700)

    assert [ok: :ok] =
             1..5 |> Task.async_stream(&Tarearbol.Full.asynch/1) |> Enum.to_list() |> Enum.uniq()

    Process.sleep(700)
    assert [20, 2] == Enum.map(Tarearbol.Full.state().children, &elem(&1, 1).value)

    GenServer.stop(pid)
  end
end
