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

      @impl Tarearbol.DynamicManager
      def children_specs, do: %{@pid => [payload: 0, timeout: 200]}

      @impl Tarearbol.DynamicManager
      def perform(i, _) do
        send(:erlang.binary_to_term(i), "pong")
        :halt
      end

      @impl Tarearbol.DynamicManager
      def call(:ping, _from, {id, payload}) do
        {:pong, {id, payload}}
      end

      @impl Tarearbol.DynamicManager
      def cast(:+, {_id, payload}) do
        {:replace, payload + 1}
      end
    end

    defmodule PingPong2 do
      use Tarearbol.DynamicManager
      @pid :erlang.term_to_binary(self())

      @impl Tarearbol.DynamicManager
      def children_specs, do: %{@pid => [timeout: 100]}

      @impl Tarearbol.DynamicManager
      def perform(i, _) do
        send(:erlang.binary_to_term(i), "pong")
        :halt
      end
    end

    defmodule PingPong3 do
      use Tarearbol.DynamicManager
      @pid :erlang.term_to_binary(self())

      @impl Tarearbol.DynamicManager
      def children_specs, do: %{{:foo, @pid} => [timeout: 100]}

      @impl Tarearbol.DynamicManager
      def perform({:foo, pid}, _) do
        send(:erlang.binary_to_term(pid), "pong")
        {:ok, "pong"}
      end
    end

    {:ok, pid1} = PingPong1.start_link()
    {:ok, pid2} = PingPong2.start_link()
    {:ok, pid3} = PingPong3.start_link()

    this = :erlang.term_to_binary(self())
    assert PingPong1.asynch_call(this, :+) == :ok
    assert PingPong1.asynch_call(this, :+) == :ok
    assert PingPong1.synch_call(this, :ping) == {:ok, {:pong, {this, 2}}}

    assert_receive "pong", 200
    assert_receive "pong", 200
    assert_receive "pong", 200

    Process.sleep(200)

    assert PingPong1.state_module().state().children == %{}
    assert PingPong2.state_module().state().children == %{}
    refute PingPong3.state_module().state().children == %{}

    GenServer.stop(pid3)
    GenServer.stop(pid2)
    GenServer.stop(pid1)

    Enum.each([PingPong1, PingPong2, PingPong3], fn mod ->
      :code.delete(mod)
      :code.purge(mod)
      mod = Module.concat([mod, State])
      :code.delete(mod)
      :code.purge(mod)
    end)
  end

  test "tracks crashes" do
    defmodule PingPong4 do
      use Tarearbol.DynamicManager
      @pid :erlang.term_to_binary(self())

      @impl Tarearbol.DynamicManager
      def children_specs, do: %{@pid => [timeout: 100]}

      @impl Tarearbol.DynamicManager
      def perform(i, _),
        do: {:ok, send(:erlang.binary_to_term(i), "pong")}
    end

    {:ok, pid4} = PingPong4.start_link()
    assert_receive "pong", 200
    PingPong4.put(:erlang.term_to_binary(self()), timeout: 100)
    assert_receive "pong", 200
    PingPong4.put(:erlang.term_to_binary(self()), timeout: 100)
    assert map_size(PingPong4.state_module().state().children) == 1
    assert_receive "pong", 200
    PingPong4.del(:erlang.term_to_binary(self()))
    Process.sleep(10)
    assert map_size(PingPong4.state_module().state().children) == 0
    GenServer.stop(pid4)

    Enum.each([PingPong4], fn mod ->
      :code.delete(mod)
      :code.purge(mod)
      mod = Module.concat([mod, State])
      :code.delete(mod)
      :code.purge(mod)
    end)
  end
end
