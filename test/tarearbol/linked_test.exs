defmodule Tarearbol.Linked.Test do
  use ExUnit.Case, async: false

  test "tasks that outlive their spawner" do
    %Task{owner: owner, pid: pid, ref: _ref} = task = Tarearbol.Linked.run(fn() ->
      :timer.sleep 50
    end)

    :timer.sleep 20
    assert self() == owner
    assert Tarearbol.Application.children() == [pid]
    Task.await(task)

    case Tarearbol.Application.kill(pid) do
      {:error, :dead} ->
        assert [] == Tarearbol.Application.children()
      whatever -> assert whatever == nil
    end
  end
end
