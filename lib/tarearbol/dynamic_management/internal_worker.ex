defmodule Tarearbol.InternalWorker do
  @moduledoc false
  use GenServer

  def start_link(manager: manager),
    do: GenServer.start_link(__MODULE__, [manager: manager], name: __MODULE__)

  @impl GenServer
  def init(opts), do: {:ok, opts, {:continue, :init}}

  @spec put(id :: binary(), runner :: Tarearbol.DynamicManager.runner()) :: pid()
  def put(id, runner), do: GenServer.call(__MODULE__, {:put, id, runner})

  @spec del(id :: binary()) :: :ok
  def del(id), do: GenServer.call(__MODULE__, {:del, id})

  @spec get(id :: binary()) :: :ok
  def get(id), do: GenServer.call(__MODULE__, {:get, id})

  @impl GenServer
  def handle_continue(:init, [manager: manager] = state) do
    Enum.each(manager.children_specs(), &do_put/1)

    Tarearbol.DynamicManager.State.update_state(:started)
    manager.on_state_change(:started)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:get, id}, _from, state),
    do: {:reply, Tarearbol.DynamicManager.State.get(id), state}

  @impl GenServer
  def handle_call({:put, id, runner}, _from, state),
    do: {:reply, do_put({id, runner}), state}

  @impl GenServer
  def handle_call({:del, id}, _from, state) do
    result = %{pid: pid} = Tarearbol.DynamicManager.State.get(id)
    DynamicSupervisor.terminate_child(Tarearbol.DynamicSupervisor, pid)
    {:reply, result, state}
  end

  @spec do_put({id :: binary(), runner :: Tarearbol.DynamicManager.runner()}) :: pid()
  defp do_put({id, runner}) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Tarearbol.DynamicSupervisor,
        {Tarearbol.DynamicWorker, id: id, runner: runner}
      )

    Tarearbol.DynamicManager.State.put(id, %{pid: pid})
    pid
  end
end
