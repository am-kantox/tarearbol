defmodule Cloister.Monitor.Info do
  @moduledoc false

  @spec whois(term :: term()) :: node()
  def whois(term) do
    case HashRing.Managed.key_to_node(:cloister, term) do
      {:error, {:invalid_ring, :no_nodes}} ->
        Cloister.Monitor.nodes!()
        whois(term)

      node ->
        node
    end
  end

  @spec nodes :: [term()]
  def nodes(),
    do: HashRing.Managed.nodes(:cloister)
end
