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
    defmodule PingPong do
      use Tarearbol.DynamicManager

      @pid :erlang.term_to_binary(self())

      def children_specs do
        %{@pid => PingPong}
      end

      def runner(i) do
        send(:erlang.binary_to_term(i), "pong")
        :halt
      end
    end

    {:ok, pid} = PingPong.start_link()
    assert_receive "pong", 2_000
    Process.sleep(1_000)
    assert Tarearbol.DynamicManager.State.state().children == %{}
    GenServer.stop(pid)
  end
end
