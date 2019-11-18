defmodule Tarearbol.Scheduler.Test do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol.Scheduler

  setup do
    # with {:ok, pid} <- DynamicManager.start_link(), do: [pid: pid]
    :ok
  end

  test "receives pong from a job" do
    defmodule PingPong do
      @pid :erlang.term_to_binary(self())
      def run() do
        send(:erlang.binary_to_term(@pid), "pong")
        :halt
      end
    end

    job = Tarearbol.Scheduler.Job.create(TestJob, &PingPong.run/0, "* * * * *")

    case Tarearbol.Scheduler.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      _ -> assert false
    end

    Tarearbol.Scheduler.put("TestJob", %{payload: %{job: job}, timeout: 50})
    assert_receive "pong", 200
  end
end
