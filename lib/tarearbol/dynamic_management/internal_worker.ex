defmodule Tarearbol.InternalWorker do
  @moduledoc false
  use GenServer

  def start_link(manager: manager),
    do:
      GenServer.start_link(__MODULE__, [manager: manager], name: manager.internal_worker_module())

  @impl GenServer
  def init(opts), do: {:ok, opts, {:continue, :init}}

  @spec put(module_name :: module(), id :: binary(), opts :: Enum.t()) :: pid()
  def put(module_name, id, opts), do: GenServer.call(module_name, {:put, id, opts})

  @spec del(module_name :: module(), id :: binary()) :: :ok
  def del(module_name, id), do: GenServer.call(module_name, {:del, id})

  @spec get(module_name :: module(), id :: binary()) :: Enum.t()
  def get(module_name, id), do: GenServer.call(module_name, {:get, id})

  @impl GenServer
  def handle_continue(:init, [manager: manager] = state) do
    Enum.each(manager.children_specs(), &do_put(manager, &1))

    manager.state_module.update_state(:started)
    manager.handle_state_change(:started)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:put, id, opts}, _from, [manager: manager] = state),
    do: {:reply, do_put(manager, {id, opts}), state}

  @impl GenServer
  def handle_call({:del, id}, _from, [manager: manager] = state),
    do: {:reply, do_del(manager, id), state}

  @impl GenServer
  def handle_call({:get, id}, _from, [manager: manager] = state),
    do: {:reply, do_get(manager, id), state}

  @spec do_put(manager :: module(), {id :: any(), opts :: Enum.t()}) :: pid()
  defp do_put(manager, {id, opts}) do
    do_del(manager, id)

    {:ok, pid} =
      DynamicSupervisor.start_child(
        manager.dynamic_supervisor_module(),
        {Tarearbol.DynamicWorker, opts |> Map.new() |> Map.merge(%{id: id, manager: manager})}
      )

    manager.state_module().put(id, %{pid: pid})
    pid
  end

  @spec do_del(manager :: module(), id :: binary()) :: map()
  defp do_del(manager, id) do
    manager
    |> do_get(id)
    |> case do
      %{pid: pid} = found ->
        manager.state_module().del(id)
        DynamicSupervisor.terminate_child(manager.dynamic_supervisor_module(), pid)
        found

      _ ->
        {:error, :not_found}
    end
  end

  @spec do_get(manager :: module(), id :: binary()) :: map()
  defp do_get(manager, id), do: manager.state_module().get(id, %{})
end
