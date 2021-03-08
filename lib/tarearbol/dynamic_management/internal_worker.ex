defmodule Tarearbol.InternalWorker do
  @moduledoc false

  use Boundary

  use GenServer

  alias Tarearbol.DynamicManager

  def start_link(manager: manager),
    do:
      GenServer.start_link(__MODULE__, [manager: manager], name: manager.internal_worker_module())

  @impl GenServer
  def init(opts), do: {:ok, opts, {:continue, :init}}

  @spec put(module_name :: module(), id :: DynamicManager.id(), opts :: Enum.t()) :: :ok
  def put(module_name, id, opts), do: GenServer.cast(module_name, {:put, id, opts})

  @spec del(module_name :: module(), id :: DynamicManager.id()) :: :ok
  def del(module_name, id), do: GenServer.cast(module_name, {:del, id})

  case Code.ensure_compiled(Cloister) do
    {:module, Cloister} ->
      @spec multiput(module_name :: module(), id :: DynamicManager.id(), opts :: Enum.t()) ::
              :abcast
      def multiput(module_name, id, opts),
        do: Cloister.multicast(module_name, {:put, id, opts})

      @spec multidel(module_name :: module(), id :: DynamicManager.id()) :: :abcast
      def multidel(module_name, id),
        do: Cloister.multicast(module_name, {:del, id})

    {:error, _} ->
      require Logger

      @spec multiput(module_name :: module(), id :: DynamicManager.id(), opts :: Enum.t()) :: :ok
      def multiput(module_name, id, opts) do
        Logger.warn(
          "multidel/3 function is unavailable: Cloister cannot be found.\nUsing local `del/3` instead"
        )

        put(module_name, id, opts)
      end

      @spec multidel(module_name :: module(), id :: DynamicManager.id()) :: :ok
      def multidel(module_name, id) do
        Logger.warn(
          "multiput/3 function is unavailable: Cloister cannot be found.\nUsing local `put/3` instead"
        )

        del(module_name, id)
      end
  end

  @spec get(module_name :: module(), id :: DynamicManager.id()) :: Enum.t()
  def get(module_name, id), do: GenServer.call(module_name, {:get, id})

  @spec restart(module_name :: module()) :: :ok
  def restart(module_name), do: GenServer.cast(module_name, :restart)

  @impl GenServer
  def handle_continue(:init, [manager: manager] = state) do
    Enum.each(manager.children_specs(), &do_put(manager, &1))

    manager.state_module().update_state(:started)
    manager.handle_state_change(:started)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:put, id, opts}, [manager: manager] = state) do
    do_put(manager, {id, opts})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:restart, [manager: manager] = state) do
    manager.state_module()
    |> Process.whereis()
    |> Process.exit(:shutdown)

    {:noreply, :shutdown, state}
  end

  @impl GenServer
  def handle_cast({:del, id}, [manager: manager] = state) do
    do_del(manager, id)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:get, id}, _from, [manager: manager] = state),
    do: {:reply, do_get(manager, id), state}

  @spec do_put(manager :: module(), {id :: DynamicManager.id(), opts :: Enum.t()}) :: pid()
  defp do_put(manager, {id, opts}) do
    do_del(manager, id)

    name = {:via, Registry, {manager.registry_module(), id}}

    {:ok, pid} =
      DynamicSupervisor.start_child(
        manager.dynamic_supervisor_module(),
        {Tarearbol.DynamicWorker,
         opts |> Map.new() |> Map.merge(%{id: id, manager: manager, name: name})}
      )

    manager.state_module().put(id, %{pid: name, opts: opts})
    pid
  end

  @spec do_del(manager :: module(), id :: DynamicManager.id()) :: map() | {:error, :not_found}
  defp do_del(manager, id) do
    manager
    |> do_get(id)
    |> case do
      %{pid: {:via, Registry, {_, ^id}}} = found ->
        manager.state_module().del(id)

        case Registry.lookup(manager.registry_module(), id) do
          [{pid, _}] ->
            DynamicSupervisor.terminate_child(manager.dynamic_supervisor_module(), pid)
            found

          [] ->
            {:error, :not_registered}

          other ->
            {:error, {:unexpected, other}}
        end

      _ ->
        {:error, :not_found}
    end
  end

  @spec do_get(manager :: module(), id :: DynamicManager.id()) :: map()
  defp do_get(manager, id), do: manager.state_module().get(id, %{})
end
