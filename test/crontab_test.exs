defmodule Tarearbol.Crontab.Test do
  @moduledoc false

  use ExUnit.Case
  doctest Tarearbol.Crontab
  doctest Tarearbol.Calendar

  setup do
    :ok
  end

  test "responds with :not_found on a non-existing child" do
    #    assert {:error, :not_found} == Tarearbol.Application.kill(self())
  end
end
