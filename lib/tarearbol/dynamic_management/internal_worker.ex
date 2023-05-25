defmodule Tarearbol.InternalWorker do
  @moduledoc false

  use Boundary, deps: [Tarearbol.Telemetria, Tarearbol.DynamicManager]

  use GenServer
  use Tarearbol.Telemetria

  require Logger

  alias Tarearbol.DynamicManager

  def start_link(manager: manager),
    do:
      GenServer.start_link(__MODULE__, [manager: manager],
        name: manager.__internal_worker_module__()
      )

  @impl GenServer
  def init(opts), do: {:ok, opts, {:continue, :init}}

  case Code.ensure_compiled(Cloister) do
    {:module, Cloister} ->
      @spec start_child(worker :: module(), opts :: Enum.t()) :: any()
      def start_child(worker, opts) do
        [node() | Node.list()]
        |> Cloister.multiapply(DynamicSupervisor, :start_child, [
          worker,
          {Tarearbol.DynamicWorker, opts}
        ])
        |> tap(fn apply_result ->
          Logger.debug(
            "[🌴] Request to start new worker has been performed: #{inspect(apply_result)}"
          )
        end)
      end

      @spec terminate_child(worker :: module(), name :: GenServer.name() | pid()) :: any()
      def terminate_child(worker, name) do
        [node() | Node.list()]
        |> Cloister.multiapply(__MODULE__, :terminate_local_child, [worker, name])
        |> tap(fn apply_result ->
          Logger.debug(
            "[🌴] Request to terminate worker has been performed: #{inspect(apply_result)}"
          )
        end)
      end

    {:error, _} ->
      @spec start_child(worker :: module(), opts :: Enum.t()) :: any()
      def start_child(worker, opts),
        do: DynamicSupervisor.start_child(worker, {Tarearbol.DynamicWorker, opts})

      @spec terminate_child(worker :: module(), name :: GenServer.name() | pid()) :: any()
      def terminate_child(worker, name),
        do: terminate_local_child(worker, name)
  end

  @spec terminate_local_child(worker :: module(), name :: GenServer.name() | pid()) :: any()
  def terminate_local_child(worker, name) do
    case GenServer.whereis(name) do
      pid when is_pid(pid) -> DynamicSupervisor.terminate_child(worker, pid)
      other -> Logger.error("[🌴] Failed to terminate worker ‹" <> inspect(name) <> "›, whereis: ‹" <> other <> "›")
    end
  end


  @spec get(module_name :: module(), id :: DynamicManager.id()) :: Enum.t()
  def get(module_name, id), do: GenServer.call(module_name, {:get, id})

  @spec put(module_name :: module(), id :: DynamicManager.id(), opts :: Enum.t()) :: :ok
  def put(module_name, id, opts), do: GenServer.cast(module_name, {:put, id, opts})

  @spec put_new(module_name :: module(), id :: DynamicManager.id(), opts :: Enum.t()) :: :ok
  def put_new(module_name, id, opts), do: GenServer.cast(module_name, {:put_new, id, opts})

  @spec del(module_name :: module(), id :: DynamicManager.id()) :: :ok
  def del(module_name, id), do: GenServer.cast(module_name, {:del, id})

  @spec restart(module_name :: module()) :: :ok
  def restart(module_name), do: GenServer.cast(module_name, :restart)

  @spec multiput(module_name :: module(), id :: DynamicManager.id(), opts :: Enum.t()) :: :ok
  def multiput(module_name, id, opts) do
    Logger.warning("[🌴] `multiput/3` is deprecated, use `put/3` instead")
    put(module_name, id, opts)
  end

  @spec multidel(module_name :: module(), id :: DynamicManager.id()) :: :ok
  def multidel(module_name, id) do
    Logger.warning("[🌴] `multidel/3` function is deprecated, use `del/3` instead")
    del(module_name, id)
  end

  @impl GenServer
  def handle_continue(:init, [manager: manager] = state) do
    Enum.each(manager.children_specs(), &do_put(manager, &1, false))

    manager.__state_module__().update_state(:started)
    manager.handle_state_change(:started)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:put, id, opts}, [manager: manager] = state) do
    _ = do_put(manager, {id, opts}, true)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:put_new, id, opts}, [manager: manager] = state) do
    _ = do_put(manager, {id, opts}, false)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:restart, [manager: manager] = state) do
    manager.__state_module__()
    |> Process.whereis()
    |> Process.exit(:shutdown)

    {:noreply, :shutdown, state}
  end

  @impl GenServer
  def handle_cast({:del, id}, [manager: manager] = state) do
    _ = do_del(manager, id)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:get, id}, _from, [manager: manager] = state),
    do: {:reply, do_get(manager, id), state}

  if Tarearbol.Telemetria.use?(), do: @telemetria(Tarearbol.Telemetria.apply_options())

  @spec do_put(
          manager :: module(),
          {id :: DynamicManager.id(), opts :: Enum.t()},
          delete? :: boolean()
        ) :: {:ok, pid()}
  defp do_put(manager, {id, opts}, delete?) do
    _ = if delete?, do: do_del(manager, id)

    name = {:via, Registry, {manager.__registry_module__(), id}}

    updater = fn
      %DynamicManager.Child{} -> :ignore
      nil -> {:update, struct(DynamicManager.Child, %{pid: name, opts: opts})}
    end

    manager
    |> do_get_and_update(id, updater)
    |> case do
      %DynamicManager.Child{pid: pid} ->
        {:ok, pid}

      nil ->
        worker_opts = opts |> Map.new() |> Map.merge(%{id: id, manager: manager, name: name})
        start_child(manager.__dynamic_supervisor_module__(), worker_opts)
    end
  end

  @spec do_del(manager :: module(), id :: DynamicManager.id()) ::
          struct() | {:error, :not_found | :not_registered}
  defp do_del(manager, id) do
    manager
    |> do_get_and_update(id, fn _ -> :remove end)
    |> case do
      %DynamicManager.Child{pid: pid} = found ->
        if is_pid(GenServer.whereis(pid)) do
          {_, _} = terminate_child(manager.__dynamic_supervisor_module__(), pid)
          found
        else
          {:error, :not_registered}
        end

      _ ->
        {:error, :not_found}
    end
  end

  @spec do_get(manager :: module(), id :: DynamicManager.id()) :: map()
  defp do_get(manager, id), do: manager.__state_module__().get(id, %{})

  @spec do_get_and_update(
          manager :: module(),
          id :: DynamicManager.id(),
          fun ::
            (DynamicManager.Child.t() | nil ->
               :ignore | :remove | {:update, DynamicManager.Child.t() | nil})
        ) :: map() | nil
  defp do_get_and_update(manager, id, fun), do: manager.__state_module__().get_and_update(id, fun)
end
