defmodule TarearbolTest do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol

  setup do
    Tarearbol.Cron.clear!()
  end

  test "responds with :not_found on a non-existing child" do
    assert {:error, :not_found} == Tarearbol.Application.kill(self())
  end

  test "supports :ok and {:ok, _} as successful returns" do
    assert [{:ok, :ok}, {:ok, 42}] ==
             Enum.map([:ok, {:ok, 42}], fn e ->
               Tarearbol.Job.ensure(fn -> e end, accept_not_ok: false, attempts: 1)
             end)

    assert [{:ok, :ok}, {:ok, 42}] ==
             [:ok, {:ok, 42}]
             |> Enum.map(fn result -> fn -> result end end)
             |> Tarearbol.ensure_all(accept_not_ok: false, attempts: 1)
  end

  test "supports infinite re-execution until not raised" do
    assert {:ok, 42} ==
             Tarearbol.Job.ensure(
               fn ->
                 if Enum.random([1, 2]) == 1, do: 42, else: raise("¡!")
               end,
               delay: 10
             )

    assert {:ok, 42} == Tarearbol.Job.ensure({Tarearbol.TestTask, :run_raise, []}, delay: 10)

    assert 42 ==
             Tarearbol.Job.ensure!(
               fn ->
                 if Enum.random([1, 2]) == 1, do: 42, else: raise("¡!")
               end,
               delay: 10
             )
  end

  test "supports infinite re-execution until succeeded" do
    assert {:ok, 42} ==
             Tarearbol.Job.ensure(
               fn ->
                 if Enum.random([1, 2]) == 1, do: 42, else: {:ok, 42}
               end,
               delay: 10,
               accept_not_ok: false
             )
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
    assert {:error, _} = Tarearbol.Job.ensure(fn -> raise "¡!" end, attempts: 2, delay: 10)

    result = Tarearbol.Job.ensure(fn -> 42 end, attempts: 2, delay: 10, accept_not_ok: false)
    assert {:error, %{outcome: outcome, job: _}} = result
    assert outcome == 42
  end

  test "#run_in" do
    # active children
    count = Enum.count(Tarearbol.Application.children())
    pid = self()

    Tarearbol.Errand.run_in(
      fn ->
        send(pid, :yo)
        Process.sleep(100)
      end,
      100
    )

    Process.sleep(50)
    assert Enum.count(Tarearbol.Application.children()) == count + 1
    Process.sleep(100)
    assert Enum.count(Tarearbol.Application.children()) == count + 2
    Process.sleep(100)
    assert_received :yo
    assert Enum.count(Tarearbol.Application.children()) == count

    # dets
    count = Enum.count(Tarearbol.Cron.jobs())
    Tarearbol.Errand.run_in({Tarearbol.Runner, :yo!, [self()]}, 100)
    Process.sleep(50)
    assert Enum.count(Tarearbol.Cron.jobs()) == count + 1
    assert Tarearbol.Cron.jobs() == Tarearbol.Application.jobs()
    Process.sleep(100)
    assert_received :yo
    assert Enum.count(Tarearbol.Cron.jobs()) == count
  end

  @tag :skip
  test "#run_in repeatedly" do
    count = Enum.count(Tarearbol.Application.children())
    Tarearbol.Errand.run_in(fn -> Process.sleep(100) end, 100, repeatedly: true)
    Process.sleep(50)
    assert Enum.count(Tarearbol.Application.children()) == count + 1
    Process.sleep(100)
    assert Enum.count(Tarearbol.Application.children()) == count + 2
    Process.sleep(100)
    assert Enum.count(Tarearbol.Application.children()) == count + 2
  end

  test "#run_at" do
    count = Enum.count(Tarearbol.Application.children())

    run_at =
      DateTime.utc_now()
      |> DateTime.to_unix(:millisecond)
      |> Kernel.+(100)
      |> DateTime.from_unix!(:millisecond)

    Tarearbol.Errand.run_at(fn -> Process.sleep(100) end, run_at)
    Process.sleep(50)
    assert Enum.count(Tarearbol.Application.children()) == count + 1
    Process.sleep(100)
    assert Enum.count(Tarearbol.Application.children()) == count + 2
    Process.sleep(100)
    assert Enum.count(Tarearbol.Application.children()) == count
  end

  test "#drain" do
    count = Enum.count(Tarearbol.Application.children())
    Tarearbol.Errand.run_in(fn -> {:ok, 42} end, 1_000)
    Tarearbol.Errand.run_in(fn -> {:ok, 42} end, 1_000)
    Process.sleep(50)
    assert Enum.count(Tarearbol.Application.children()) == count + 2
    assert Tarearbol.drain() == [ok: 42, ok: 42]
    assert Enum.count(Tarearbol.Application.children()) == 0
  end

  @tag :skip
  test "supports long running tasks" do
    result = Tarearbol.Job.ensure(fn -> Process.sleep(6_000) end, attempts: 1, timeout: 10_000)
    assert {:ok, :ok} = result
    result = Tarearbol.Job.ensure(fn -> Process.sleep(6_000) end, attempts: 1)
    assert {:error, %{outcome: nil, job: _}} = result
  end

  test "many async stream ensured" do
    res =
      1..20
      |> Enum.map(fn i ->
        fn -> Process.sleep(Enum.random(1..i)) end
      end)
      |> Tarearbol.ensure_all(attempts: 1)
      |> Enum.map(fn {result, _} -> result end)

    assert res == List.duplicate(:ok, 20)
  end

  test "many async stream ensured with raises" do
    res =
      1..20
      |> Enum.map(fn i ->
        fn ->
          tos = Enum.random(i..100)
          if tos > 80, do: raise("YO")
          Process.sleep(tos)
        end
      end)
      |> Tarearbol.ensure_all()
      |> Enum.map(fn {result, _} -> result end)

    assert res == List.duplicate(:ok, 20)
  end

  test "ensure all does not hang up" do
    res = Tarearbol.ensure_all([])
    assert res == []
  end

  test "many async stream ensured with errors" do
    res =
      1..20
      |> Enum.map(fn _ ->
        fn -> raise "¡!" end
      end)
      |> Tarearbol.ensure_all(attempts: 1, raise: false)
      |> Enum.map(fn {result, _} -> result end)

    assert res == List.duplicate(:error, 20)
  end

  @tag :skip
  test "many async long-running stream ensured" do
    IO.inspect(DateTime.utc_now(), label: "⇒")

    res =
      1..6
      |> Enum.map(fn _ ->
        fn -> Process.sleep(6_000) end
      end)
      |> Tarearbol.ensure_all(attempts: 1, max_concurrency: 8, timeout: 10_000)
      |> Enum.map(fn {result, _} -> result end)

    IO.inspect(DateTime.utc_now(), label: "⇐")

    assert res == List.duplicate(:ok, 6)
  end

  # test "many async stream ensured with errors raised" do
  #   assert_raise(Tarearbol.TaskFailedError, fn ->
  #     1..1
  #     |> Enum.map(fn _ ->
  #       fn -> raise "¡!" end
  #     end)
  #     |> Tarearbol.ensure_all(attempts: 1, raise: true)
  #   end)
  # end
end
