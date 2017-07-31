defmodule TarearbolTest do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol

  test "responds with :not_found on a non-existing child" do
    assert {:error, :not_found} == Tarearbol.Application.kill(self())
  end

  test "supports infinite re-execution until not raised" do
    assert {:ok, 42} ==
      Tarearbol.Job.ensure fn ->
        if Enum.random([1, 2]) == 1, do: 42, else: raise "¡!"
      end, delay: 10

    assert {:ok, 42} ==
      Tarearbol.Job.ensure {Tarearbol.TestTask, :run_raise, []}, delay: 10

    assert 42 ==
      Tarearbol.Job.ensure! fn ->
        if Enum.random([1, 2]) == 1, do: 42, else: raise "¡!"
      end, delay: 10
  end

  test "supports infinite re-execution until succeeded" do
    assert {:ok, 42} ==
      Tarearbol.Job.ensure fn ->
        if Enum.random([1, 2]) == 1, do: 42, else: {:ok, 42}
      end, delay: 10, accept_not_ok: false
  end

  test "supports finite amount of attempts and raises or returns error" do
    assert_raise(Tarearbol.TaskFailedError, fn ->
      Tarearbol.Job.ensure(fn -> raise "¡!" end, attempts: 2, delay: 10, raise: true)
    end)
    assert_raise(Tarearbol.TaskFailedError, fn ->
      Tarearbol.Job.ensure!(fn -> {:error, 42} end, attempts: 2, delay: 10, raise: true)
    end)
  end

  test "supports finite amount of attempts and returns error" do
    assert {:error, _} =
      Tarearbol.Job.ensure fn -> raise "¡!" end, attempts: 2, delay: 10

    result = Tarearbol.Job.ensure fn -> 42 end, attempts: 2, delay: 10, accept_not_ok: false
    assert {:error, %{outcome: outcome, job: _}} = result
    assert outcome == 42
  end

  test "run_in and drain" do
    Tarearbol.Errand.run_in(fn -> Process.sleep(100) end, 100)
    Process.sleep(50)
    assert Enum.count(Tarearbol.Application.children) == 1
    Process.sleep(100)
    assert Enum.count(Tarearbol.Application.children) == 2
    Process.sleep(100)
    assert Enum.count(Tarearbol.Application.children) == 0

    Tarearbol.Errand.run_in(fn -> {:ok, 42} end, 1_000)
    Tarearbol.Errand.run_in(fn -> {:ok, 42} end, 1_000)
    Process.sleep(50)
    assert Enum.count(Tarearbol.Application.children) == 2
    assert Tarearbol.drain == [ok: 42, ok: 42]
    assert Enum.count(Tarearbol.Application.children) == 0
  end
end
