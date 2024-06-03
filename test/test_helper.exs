defmodule Tarearbol.TestTask do
  def run_raise() do
    if Enum.random([1, 2]) == 1, do: {:ok, 42}, else: raise("¡!")
  end

  def run_error() do
    if Enum.random([1, 2]) == 1, do: {:ok, 42}, else: {:error, 42}
  end

  def run_value() do
    if Enum.random([1, 2]) == 1, do: 42, else: {:error, 42}
  end
end

defmodule Tarearbol.Runner do
  def yo!(args) do
    with pid <- args, do: send(pid, :yo)
    {:ok, args}
  end
end

defmodule DynamicManager do
  use Tarearbol.DynamicManager

  def children_specs do
    for i <- 1..100, do: {"foo_#{i}", []}, into: %{}
  end
end

ExUnit.start(exclude: :skip, capture_log: true)
