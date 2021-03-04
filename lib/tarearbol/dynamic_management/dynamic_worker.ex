defmodule Tarearbol.DynamicWorker do
  @moduledoc false
  use Boundary, deps: [Tarearbol.InternalWorker]

  use GenServer
  require Logger

  @typedoc "ID of the worker"
  @type id :: term()

  @typedoc "Payload associated with the worker"
  @type payload :: any()

  @typedoc "Internal state of the worker"
  @type state :: %{
          id: id(),
          lull: float(),
          manager: module(),
          payload: payload(),
          timeout: integer()
        }

  @typedoc "Expected response from the DymanicManager implementation"
  @type response ::
          :halt
          | :multihalt
          | {:replace, payload()}
          | {:replace, id(), payload()}
          | {:ok, any()}
          | any()

  @default_opts %{
    timeout: 1_000,
    lull: 1.1,
    payload: nil
  }

  @spec start_link([
          {:manager, atom()}
          | {:id, any()}
          | {:payload, term()}
          | {:timeout, non_neg_integer()}
          | {:lull, float()}
        ]) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(opts) do
    opts = Map.merge(@default_opts, Map.new(opts))

    {name, opts} =
      Map.pop(
        opts,
        :name,
        {:via, Registry, {opts.manager.registry_module(), opts.id}}
      )

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    schedule_work(opts.timeout)
    {:ok, opts}
  end

  @impl GenServer
  def terminate(reason, %{manager: manager, id: id, payload: payload}),
    do: manager.terminate(reason, {id, payload})

  @impl GenServer
  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.warn("Unexpected EXIT reason " <> inspect(reason) <> "\nState:\n" <> inspect(state))
    {:stop, reason, state}
  end

  @impl GenServer
  def handle_info(:work, %{manager: manager, id: id, payload: payload} = state) do
    id
    |> manager.perform(payload)
    |> handle_response(state)
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    state.manager.handle_timeout(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(message, from, %{manager: manager, id: id, payload: payload} = state) do
    reply = manager.call(message, from, {id, payload})

    {reply, state} =
      case reply do
        {:replace, payload} ->
          {payload, %{state | payload: payload}}

        {:replace, ^id, ^payload} ->
          {payload, state}

        {:replace, ^id, payload} ->
          {payload, %{state | payload: payload}}

        {:replace, new_id, payload} ->
          Tarearbol.InternalWorker.del(manager.internal_worker_module(), id)
          Tarearbol.InternalWorker.put(manager.internal_worker_module(), new_id, payload)
          {payload, %{state | id: id, payload: payload}}

        {:ok, payload} ->
          {payload, state}

        other ->
          {other, state}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_cast(message, %{manager: manager, id: id, payload: payload} = state) do
    reply = manager.cast(message, {id, payload})

    state =
      case reply do
        {:replace, payload} ->
          %{state | payload: payload}

        {:replace, ^id, ^payload} ->
          state

        {:replace, ^id, payload} ->
          %{state | payload: payload}

        {:replace, new_id, payload} ->
          Tarearbol.InternalWorker.del(manager.internal_worker_module(), id)
          Tarearbol.InternalWorker.put(manager.internal_worker_module(), new_id, payload)
          %{state | id: id, payload: payload}

        _ ->
          state
      end

    {:noreply, state}
  end

  @spec schedule_work(timeout :: integer()) :: reference()
  defp schedule_work(timeout) when timeout <= 0, do: make_ref()
  defp schedule_work(timeout) when timeout < 100, do: schedule_work(100)
  defp schedule_work(timeout), do: Process.send_after(self(), :work, timeout)

  @spec reschedule(module(), id(), any(), integer()) :: reference()
  defp reschedule(state, id, value, timeout) do
    state.put(id, %{state.get(id) | value: value})
    schedule_work(timeout)
  end

  @spec handle_response(response(), state) :: state when state: state()
  defp handle_response(
         response,
         %{manager: manager, timeout: timeout, id: id, payload: payload, lull: lull} = state
       ) do
    case response do
      :halt ->
        Tarearbol.InternalWorker.del(manager.internal_worker_module(), id)
        state

      :multihalt ->
        Tarearbol.InternalWorker.multidel(manager.internal_worker_module(), id)
        state

      {:replace, ^payload} ->
        state

      {:replace, payload} ->
        reschedule(manager.state_module(), id, payload, timeout)
        %{state | payload: payload}

      {:replace, ^id, ^payload} ->
        state

      {:replace, ^id, payload} ->
        reschedule(manager.state_module(), id, payload, timeout)
        %{state | payload: payload}

      {:replace, new_id, payload} ->
        Tarearbol.InternalWorker.del(manager.internal_worker_module(), id)
        Tarearbol.InternalWorker.put(manager.internal_worker_module(), new_id, payload)
        schedule_work(timeout)
        %{state | id: new_id, payload: payload}

      {{:timeout, timeout}, result} ->
        reschedule(manager.state_module(), id, result, timeout * lull)
        state

      {:ok, result} ->
        reschedule(manager.state_module(), id, result, timeout)
        state

      result ->
        reschedule(manager.state_module(), id, result, timeout * lull)
        state
    end
  end
end
