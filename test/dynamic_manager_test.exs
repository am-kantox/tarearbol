defmodule Tarearbol.DynamicManager.Test do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol.DynamicManager

  setup do
    # with {:ok, pid} <- DynamicManager.start_link(), do: [pid: pid]
    :ok
  end

  test "receives pong" do
    defmodule PingPong do
      @default_timeout Application.compile_env(:tarearbol, :dynamic_timeout, 100)

      use Tarearbol.DynamicManager, defaults: [timeout: @default_timeout]

      @impl Tarearbol.DynamicManager
      def children_specs, do: %{:foo => [payload: %{value: 0, pid: nil}, timeout: 200]}

      @impl Tarearbol.DynamicManager
      def perform(_id, %{pid: nil} = state), do: {:ok, state}

      def perform(_id, %{pid: pid}) do
        send(pid, "pong")
        :halt
      end

      @impl Tarearbol.DynamicManager
      def call(:ping, _from, {id, payload}) do
        {:pong, {id, payload.value}}
      end

      @impl Tarearbol.DynamicManager
      def cast(:+, {_id, %{value: value, pid: pid}}) do
        {:replace, %{value: value + 1, pid: pid}}
      end

      def cast({:down, pid}, {_id, %{value: value, pid: nil}}) do
        {:replace, %{value: value, pid: pid}}
      end
    end

    {:ok, pid} = PingPong.start_link()
    Process.sleep(200)

    this = :foo
    assert PingPong.asynch_call(this, :+) == :ok
    Process.sleep(200)
    assert PingPong.asynch_call(this, :+) == :ok
    Process.sleep(200)
    assert PingPong.synch_call(this, :ping) == {:ok, [pong: {this, 2}]}

    assert PingPong.asynch_call(this, {:down, self()}) == :ok
    Process.sleep(1_000)

    assert PingPong.state().children == %{}

    GenServer.stop(pid)

    Enum.each([PingPong], fn mod ->
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
    assert map_size(PingPong4.state().children) == 1
    assert_receive "pong", 200
    PingPong4.del(:erlang.term_to_binary(self()))
    Process.sleep(10)
    assert map_size(PingPong4.state().children) == 0
    GenServer.stop(pid4)

    Enum.each([PingPong4], fn mod ->
      :code.delete(mod)
      :code.purge(mod)
      mod = Module.concat([mod, State])
      :code.delete(mod)
      :code.purge(mod)
    end)
  end

  test "timeout" do
    defmodule PingPong5 do
      use Tarearbol.DynamicManager
      @pid :erlang.term_to_binary(self())

      @impl Tarearbol.DynamicManager
      def children_specs, do: %{@pid => [timeout: 100, payload: 100]}

      @impl Tarearbol.DynamicManager
      def perform(i, timeout) do
        send(:erlang.binary_to_term(i), "pong")
        {{:timeout, timeout * 10}, timeout * 10}
      end
    end

    {:ok, pid5} = PingPong5.start_link()
    refute_receive "pong", 50
    assert_receive "pong", 500
    refute_receive "pong", 300
    assert_receive "pong", 1_000
    PingPong5.del(:erlang.term_to_binary(self()))
    Process.sleep(10)
    assert map_size(PingPong5.state().children) == 0
    GenServer.stop(pid5)

    Enum.each([PingPong5], fn mod ->
      :code.delete(mod)
      :code.purge(mod)
      mod = Module.concat([mod, State])
      :code.delete(mod)
      :code.purge(mod)
    end)
  end
end
