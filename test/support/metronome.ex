defmodule Tarearbol.Metronome do
  @moduledoc false
  use Tarearbol.DynamicManager, defaults: [instant_perform?: true]

  def children_specs do
    for id <- ?a..?c, into: %{}, do: {<<id>>, [timeout: 5_000]}
  end

  def perform(id, _) do
    if Cloister.mine?(id), do: IO.inspect({id, node()})
    {:ok, {node(), id}}
  end
end
