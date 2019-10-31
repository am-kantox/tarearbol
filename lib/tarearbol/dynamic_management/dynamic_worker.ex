defmodule Tarearbol.DynamicWorker do
  @moduledoc false
  use GenServer

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
        {:via, Registry, {Module.concat(opts.manager.namespace(), Registry), opts.id}}
      )

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    schedule_work(opts.timeout)
    {:ok, opts}
  end

  @impl GenServer
  def handle_info(:work, state) do
    %{manager: manager, id: id, payload: payload, timeout: timeout, lull: lull} = state

    case manager.perform(id, payload) do
      :halt ->
        Tarearbol.InternalWorker.del(manager.internal_worker_module(), id)
        {:noreply, state}

      {:replace, id, payload} ->
        Tarearbol.InternalWorker.put(manager.internal_worker_module(), id, payload)
        Tarearbol.InternalWorker.del(manager.internal_worker_module(), id)
        {:noreply, state}

      {{:timeout, timeout}, result} ->
        do_handle_work(manager.state_module(), id, result, timeout)
        {:noreply, state, round(timeout * lull)}

      {:ok, result} ->
        do_handle_work(manager.state_module(), id, result, timeout)
        {:noreply, state, round(timeout * lull)}

      result ->
        do_handle_work(manager.state_module(), id, result, timeout)
        {:noreply, state, round(timeout * lull)}
    end
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    state.manager.handle_timeout(state)
    {:noreply, state}
  end

  @spec do_handle_work(
          state :: atom(),
          id :: any(),
          result :: any(),
          timeout :: non_neg_integer()
        ) :: reference()
  defp do_handle_work(state, id, result, timeout) do
    state.put(id, %{state.get(id) | value: result})
    schedule_work(timeout)
  end

  @spec schedule_work(timeout :: non_neg_integer()) :: reference()
  defp schedule_work(timeout),
    do: Process.send_after(self(), :work, timeout)
end
