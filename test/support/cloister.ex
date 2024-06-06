if match?({:module, Cloister}, Code.ensure_compiled(Cloister)) do
  defmodule Cloister.Monitor.Info do
    @moduledoc false

    use Boundary

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

  defmodule Cloister.Listener.Default do
    @moduledoc false

    use Boundary

    @behaviour Cloister.Listener
    require Logger

    def on_state_change(from, to, state) do
      Logger.debug("[🕸️ @#{node()}] 🔄 from: #{from}, state: " <> inspect(state))
    end
  end
end
