defmodule Tarearbol.DynamicManager.Test do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol.DynamicManager

  setup do
    with {:ok, pid} <- DynamicManager.start_link(), do: [pid: pid]
  end

  test "responds with :not_found on a non-existing child" do
    # assert {:error, :not_found} == Tarearbol.Application.kill(self())
  end
end
