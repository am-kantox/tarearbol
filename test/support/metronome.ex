defmodule Tarearbol.Metronome do
  @moduledoc false
  use Tarearbol.DynamicManager

  def children_specs do
    for id <- ?a..?d, into: %{}, do: {<<id>>, [timeout: 1_000]}
  end

  def perform(id, _) do
    if Cloister.mine?(id), do: IO.inspect({id, node()})
    {:ok, {node(), id}}
  end
end
