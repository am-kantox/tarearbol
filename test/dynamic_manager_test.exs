defmodule Tarearbol.DynamicManager.Test do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol.DynamicManager

  setup do
    # with {:ok, pid} <- DynamicManager.start_link(), do: [pid: pid]
    :ok
  end

  test "receives pong" do
    defmodule PingPong1 do
      use Tarearbol.DynamicManager
      @pid :erlang.term_to_binary(self())
      def children_specs, do: %{@pid => [timeout: 100]}

      def perform(i, _) do
        send(:erlang.binary_to_term(i), "pong")
        :halt
      end
    end

    defmodule PingPong2 do
      use Tarearbol.DynamicManager
      @pid :erlang.term_to_binary(self())
      def children_specs, do: %{@pid => [timeout: 100]}

      def perform(i, _) do
        send(:erlang.binary_to_term(i), "pong")
        :halt
      end
    end

    defmodule PingPong3 do
      use Tarearbol.DynamicManager
      @pid :erlang.term_to_binary(self())
      def children_specs, do: %{{:foo, @pid} => [timeout: 100]}

      def perform({:foo, pid}, _) do
        send(:erlang.binary_to_term(pid), "pong")
        {:ok, "pong"}
      end
    end

    {:ok, pid1} = PingPong1.start_link()
    {:ok, pid2} = PingPong2.start_link()
    {:ok, pid3} = PingPong3.start_link()

    assert_receive "pong", 200
    assert_receive "pong", 200
    assert_receive "pong", 200

    Process.sleep(100)

    assert PingPong1.state_module().state().children == %{}
    assert PingPong2.state_module().state().children == %{}
    refute PingPong3.state_module().state().children == %{}

    GenServer.stop(pid3)
    GenServer.stop(pid2)
    GenServer.stop(pid1)
  end

  test "tracks crashes" do
    defmodule PingPong3 do
      use Tarearbol.DynamicManager
      @pid :erlang.term_to_binary(self())
      def children_specs, do: %{@pid => [timeout: 100]}

      def perform(i, _),
        do: {:ok, send(:erlang.binary_to_term(i), "pong")}
    end

    {:ok, pid3} = PingPong3.start_link()
    assert_receive "pong", 200
    PingPong3.put(:erlang.term_to_binary(self()), timeout: 100)
    assert_receive "pong", 200
    PingPong3.put(:erlang.term_to_binary(self()), timeout: 100)
    assert map_size(PingPong3.state_module().state().children) == 1
    assert_receive "pong", 200
    PingPong3.del(:erlang.term_to_binary(self()))
    Process.sleep(10)
    assert map_size(PingPong3.state_module().state().children) == 0
    GenServer.stop(pid3)
  end
end
