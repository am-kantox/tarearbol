defmodule Tarearbol.DynamicWorker do
  @moduledoc false
  use GenServer

  def start_link(opts),
    do:
      GenServer.start_link(
        __MODULE__,
        opts |> Map.new() |> Map.put_new(:timeout, 1_000) |> Map.put_new(:lull, 1.1)
      )

  @impl GenServer
  def init(opts) do
    schedule_work(opts.timeout)
    {:ok, opts}
  end

  @impl GenServer
  def handle_info(:work, state) do
    case state.manager.process(state.id, state.arg) do
      :halt ->
        Tarearbol.InternalWorker.del(manager.internal_worker_module(), state.id)
        {:noreply, state}

      result ->
        updated =
          state.id
          |> manager.state_module().get()
          |> Map.put(:value, result)

        manager.state_module().put(state.id, updated)

        schedule_work(state.timeout)
        {:noreply, state, round(state.timeout * state.lull)}
    end
  end
  
  @impl GenServer
  def handle_info(:timeout, state), do: state.manager.handle_timeout(state)

  defp schedule_work(timeout) do
    Process.send_after(self(), :work, timeout)
  end
end
