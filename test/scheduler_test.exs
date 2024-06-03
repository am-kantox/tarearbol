defmodule Tarearbol.Scheduler.Test do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol.Scheduler

  test "Job.create/3 + Scheduler.put/3" do
    defmodule Pong1 do
      @moduledoc false
      @pid :erlang.term_to_binary(self())
      def run, do: {:ok, send(:erlang.binary_to_term(@pid), "pong-1")}
    end

    job = Tarearbol.Scheduler.Job.create(PongJob1, &Pong1.run/0, "* * * * *")
    Tarearbol.Scheduler.put("PutTestJob", %{payload: %{job: job}, timeout: 100})
    assert_receive "pong-1", 200
  end

  @tag timeout: :infinity
  test "push/3 → crontab" do
    defmodule Pong2 do
      @moduledoc false
      @pid :erlang.term_to_binary(self())
      def run, do: send(:erlang.binary_to_term(@pid), "pong-2")
    end

    Tarearbol.Scheduler.push(PongJob2, &Pong2.run/0, 100)
    assert_receive "pong-2", 200

    defmodule Pong3 do
      @moduledoc false
      @pid :erlang.term_to_binary(self())
      def run, do: send(:erlang.binary_to_term(@pid), "pong-3")
    end

    Tarearbol.Scheduler.push(PongJob3, &Pong3.run/0, "* * * * *")
    assert_receive "pong-3", 60_000
  end
end
