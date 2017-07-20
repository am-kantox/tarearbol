defmodule Tarearbol.Simple.Test do
  use ExUnit.Case, async: false

  test "tasks that outlive their spawner" do
    pid = self()
    spawn(fn() ->
      Tarearbol.Simple.run(fn() ->
        :timer.sleep 50
        send(pid, {:sup, self()})
      end)
      Process.exit(self(), :kill)
    end)

    :timer.sleep 20
    case Tarearbol.Application.children() do
      [task_pid] ->
        assert is_pid(task_pid)
        :timer.sleep 40
        assert_receive {:sup, ^task_pid}
      whatever -> assert whatever == nil
    end
  end

  test "successfully terminates a child" do
    {:ok, task} = Tarearbol.Simple.run(fn() ->
      :timer.sleep 50
    end)

    :timer.sleep 20
    assert Tarearbol.Application.children() == [task]
    case Tarearbol.Application.kill(task) do
      :ok ->
        assert [] == Tarearbol.Application.children()
        :timer.sleep 40
        assert {:error, :dead} == Tarearbol.Application.kill(task)
      whatever -> assert whatever == nil
    end
  end
end
