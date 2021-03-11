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

    assert {:ok, 1} = Tarearbol.Full.synch()
    assert {:ok, _} = Tarearbol.Full.synch()
    assert {:ok, _} = Tarearbol.Full.synch(3)

    assert 5 ==
             Tarearbol.Full.state().children
             |> Enum.map(&elem(&1, 1).value)
             |> Enum.reject(&is_nil/1)
             |> Enum.sum()

    assert Tarearbol.Full.asynch() == :ok
    Process.sleep(10)
    assert Tarearbol.Full.asynch() == :ok
    Process.sleep(10)
    assert Tarearbol.Full.asynch() == :error
    Process.sleep(700)

    assert [ok: :ok] =
             1..5 |> Task.async_stream(&Tarearbol.Full.asynch/1) |> Enum.to_list() |> Enum.uniq()

    Process.sleep(700)

    assert 20 ==
             Tarearbol.Full.state().children
             |> Enum.map(&elem(&1, 1).value)
             |> Enum.reject(&is_nil/1)
             |> Enum.sum()

    GenServer.stop(pid)
  end
end
