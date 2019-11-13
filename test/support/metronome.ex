defmodule Tarearbol.Metronome do
  @moduledoc false
  use Tarearbol.DynamicManager

  def children_specs,
    do: for(id <- ?a..?z, into: %{}, do: {<<id>>, [timeout: 1_000]})

  def perform(id, _), do: {:ok, id}
end
