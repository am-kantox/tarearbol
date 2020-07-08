defmodule Tarearbol.Scheduler.Test do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol.Scheduler

  setup_all do
    case Tarearbol.Scheduler.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      _ -> assert false
    end
  end

  test "Job.create/3 + Scheduler.put/3" do
    defmodule PingPong do
      @pid :erlang.term_to_binary(self())
      def run() do
        send(:erlang.binary_to_term(@pid), "pong")
        :halt
      end
    end

    job = Tarearbol.Scheduler.Job.create(PutTestJob, &PingPong.run/0, "* * * * *")
    Tarearbol.Scheduler.put("PutTestJob", %{payload: %{job: job}, timeout: 50})
    assert_receive "pong", 200
  end

  test "push/3 → crontab" do
    defmodule PingPong1 do
      @pid :erlang.term_to_binary(self())
      def run() do
        send(:erlang.binary_to_term(@pid), "pong")
        :halt
      end
    end

    Tarearbol.Scheduler.push(PushTestJob1, &PingPong1.run/0, "* * * * *")
    assert_receive "pong", 60_000
  end

  test "push/3 → DateTime" do
    defmodule PingPong2 do
      @pid :erlang.term_to_binary(self())
      def run() do
        send(:erlang.binary_to_term(@pid), "pong")
        :halt
      end
    end

    Tarearbol.Scheduler.push(
      PushTestJob2,
      &PingPong2.run/0,
      DateTime.add(DateTime.utc_now(), 50, :millisecond)
    )

    assert_receive "pong", 200
  end
end
