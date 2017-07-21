defmodule Tarearbol.TestTask do
  def run_raise() do
    if Enum.random([1, 2]) == 1, do: {:ok, 42}, else: raise "¡!"
  end
  def run_error() do
    if Enum.random([1, 2]) == 1, do: {:ok, 42}, else: {:error, 42}
  end
  def run_value() do
    if Enum.random([1, 2]) == 1, do: 42, else: {:error, 42}
  end
end
ExUnit.start()
