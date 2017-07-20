defmodule TarearbolTest do
  use ExUnit.Case
  doctest Tarearbol

  test "responds with :not_found on a non-existing child" do
    assert {:error, :not_found} == Tarearbol.Application.kill(self())
  end

  test "supports infinite re-execution until succeeded" do
    assert {:ok, 42} ==
      Tarearbol.Job.ensure fn ->
        if Enum.random([1, 2]) == 1, do: 42, else: raise "¡!"
      end, delay: 10

    assert 42 ==
      Tarearbol.Job.ensure! fn ->
        if Enum.random([1, 2]) == 1, do: 42, else: raise "¡!"
      end, delay: 10
  end

  test "supports finite amount of attempts and raises" do
    assert_raise(Tarearbol.TaskFailedError, fn ->
      Tarearbol.Job.attempts(fn -> raise "¡!" end, 2, delay: 10, raise: true)
    end)
  end

  test "supports finite amount of attempts and returns error" do
    assert {:error, _} =
      Tarearbol.Job.attempts fn -> raise "¡!" end, 2, delay: 10
  end
end
