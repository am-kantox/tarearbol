defmodule Tarearbol.DynamicManager.Test do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol.DynamicManager

  setup do
    # with {:ok, pid} <- DynamicManager.start_link(), do: [pid: pid]
    :ok
  end

  test "responds with :not_found on a non-existing child" do
    # assert {:error, :not_found} == Tarearbol.Application.kill(self())
  end

  test "receives pong" do
    defmodule PingPong1 do
      use Tarearbol.DynamicManager

      @pid :erlang.term_to_binary(self())

      def children_specs do
        %{@pid => PingPong1}
      end

      def runner(i) do
        send(:erlang.binary_to_term(i), "pong")
        :halt
      end
    end

    defmodule PingPong2 do
      use Tarearbol.DynamicManager

      @pid :erlang.term_to_binary(self())

      def children_specs do
        %{@pid => PingPong2}
      end

      def runner(i) do
        send(:erlang.binary_to_term(i), "pong")
        :halt
      end
    end

    {:ok, pid1} = PingPong1.start_link()
    {:ok, pid2} = PingPong2.start_link()
    assert_receive "pong", 2_000
    assert_receive "pong", 2_000
    Process.sleep(1_000)
    assert PingPong1.state_module().state().children == %{}
    assert PingPong2.state_module().state().children == %{}
    GenServer.stop(pid2)
    GenServer.stop(pid1)
  end
end
