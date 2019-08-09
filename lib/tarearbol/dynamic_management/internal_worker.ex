defmodule Tarearbol.InternalWorker do
  use GenServer

  def start_link(manager: manager),
    do: GenServer.start_link(__MODULE__, [manager: manager], name: __MODULE__)

  @impl GenServer
  def init(opts), do: {:ok, opts, {:continue, :init}}

  @impl GenServer
  def handle_continue(:init, [manager: manager] = state) do
    Enum.each(manager.children_specs(), fn
      {id, runner} ->
        {:ok, pid} =
          DynamicSupervisor.start_child(
            Tarearbol.DynamicSupervisor,
            {Tarearbol.DynamicWorker, runner: runner}
          )

        Tarearbol.DynamicManager.State.put(id, %{pid: pid})
    end)

    Tarearbol.DynamicManager.State.update_state(:started)
    manager.on_state_change(:started)
    {:noreply, state}
  end
end
