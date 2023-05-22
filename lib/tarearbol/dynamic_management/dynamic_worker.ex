defmodule Tarearbol.DynamicWorker do
  @moduledoc false
  use Boundary, deps: [Tarearbol.InternalWorker]

  use GenServer
  require Logger

  @typedoc "Internal state of the worker"
  @type state :: %{
          id: Tarearbol.DynamicManager.id(),
          lull: float(),
          manager: module(),
          payload: Tarearbol.DynamicManager.payload(),
          timeout: integer()
        }

  @spec start_link(%{
          manager: atom(),
          id: Tarearbol.DynamicManager.id(),
          name: any(),
          payload: Tarearbol.DynamicManager.payload(),
          timeout: non_neg_integer(),
          lull: float()
        }) :: GenServer.on_start()
  def start_link(opts) do
    opts = Map.merge(opts.manager.__defaults__(), Map.new(opts))

    {name, opts} =
      Map.pop(
        opts,
        :name,
        {:via, Registry, {opts.manager.__registry_module__(), opts.id}}
      )

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    schedule_work(opts.timeout)
    {:ok, opts, {:continue, :init}}
  end

  @impl GenServer
  def handle_continue(:init, %{manager: manager, id: id, payload: payload} = state) do
    case manager.__init_handler__() do
      nil -> {:noreply, state}
      f when is_function(f, 0) -> {:noreply, %{state | payload: f.()}}
      f when is_function(f, 1) -> {:noreply, %{state | payload: f.(payload)}}
      f when is_function(f, 2) -> {:noreply, %{state | payload: f.(id, payload)}}
    end
  end

  @impl GenServer
  def terminate(reason, %{manager: manager, id: id, payload: payload}) do
    result = manager.terminate(reason, {id, payload})
    manager.__state_module__().del(id)
    result
  end

  @impl GenServer
  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.warn("Unexpected EXIT reason " <> inspect(reason) <> "\nState:\n" <> inspect(state))
    {:stop, reason, state}
  end

  @impl GenServer
  def handle_info({ref, _}, state) when is_reference(ref), do: {:noreply, state}

  @impl GenServer
  def handle_info({:payload, payload}, state),
    do: {:noreply, %{state | payload: payload}, {:continue, :init}}

  @impl GenServer
  def handle_info(:work, %{manager: manager, id: id, payload: payload} = state) do
    state =
      id
      |> handle_request(manager)
      |> manager.perform(payload)
      |> handle_response(state, true)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    state.manager.handle_timeout(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(message, from, %{manager: manager, id: id, payload: payload} = state) do
    handle_request(id, manager)
    reply = manager.call(message, from, {id, payload})
    state = handle_response(reply, state, false)

    reply =
      case reply do
        {:replace, payload} -> payload
        {:replace, _, payload} -> payload
        {:ok, payload} -> payload
        other -> other
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_cast(message, %{manager: manager, id: id, payload: payload} = state) do
    handle_request(id, manager)

    state =
      message
      |> manager.cast({id, payload})
      |> handle_response(state, false)

    {:noreply, state}
  end

  @spec schedule_work(timeout :: integer()) :: reference()
  defp schedule_work(timeout) when timeout <= 0, do: make_ref()
  defp schedule_work(timeout) when timeout < 100, do: schedule_work(100)
  defp schedule_work(timeout), do: Process.send_after(self(), :work, timeout)

  @spec handle_request(Tarearbol.DynamicManager.id(), module()) :: Tarearbol.DynamicManager.id()
  defp handle_request(id, manager) do
    manager.__state_module__().update!(id, &%{&1 | busy?: DateTime.utc_now()})
    id
  end

  @spec handle_response(Tarearbol.DynamicManager.response(), state, boolean()) ::
          state
        when state: state()
  defp handle_response(
         response,
         %{manager: manager, timeout: timeout, id: id, payload: payload, lull: lull} = state,
         reschedule
       ) do
    restate = fn value ->
      manager.__state_module__().update!(id, &%{&1 | value: value, busy?: nil})
    end

    state =
      case response do
        :halt ->
          Tarearbol.InternalWorker.del(manager.__internal_worker_module__(), id)
          state

        :multihalt ->
          Logger.warn("""
          Returning `:multihalt` from callbacks is deprecated.
          Use `distributed: true` parameter in call to `use Tarearbol.DynamicManager`
            and return regular `:halt` instead.
          """)

          Tarearbol.InternalWorker.del(manager.__internal_worker_module__(), id)
          state

        {:replace, ^payload} ->
          restate.(payload)
          state

        {:replace, payload} ->
          restate.(payload)
          %{state | payload: payload}

        {:replace, ^id, ^payload} ->
          restate.(payload)
          state

        {:replace, ^id, payload} ->
          restate.(payload)
          %{state | payload: payload}

        {:replace, new_id, payload} ->
          Tarearbol.InternalWorker.del(manager.__internal_worker_module__(), id)
          Tarearbol.InternalWorker.put(manager.__internal_worker_module__(), new_id, payload)
          %{state | id: new_id, payload: payload}

        {{:timeout, new_timeout}, result} ->
          restate.(result)
          %{state | timeout: new_timeout, payload: result, lull: lull * new_timeout / timeout}

        {:ok, result} ->
          restate.(result)
          state

        result ->
          restate.(result)
          state
      end

    _ = if reschedule, do: schedule_work(state.timeout)
    state
  end
end
