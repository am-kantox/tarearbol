defmodule Tarearbol.DynamicWorker do
  @moduledoc false
  use GenServer

  @default_timeout 1_000
  @default_lull 1.1

  @spec start_link([
          {:manager, atom()}
          | {:id, any()}
          | {:arg, term()}
          | {:timeout, non_neg_integer()}
          | {:lull, float()}
        ]) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(opts),
    do:
      GenServer.start_link(
        __MODULE__,
        opts
        |> Map.new()
        |> Map.put_new(:timeout, @default_timeout)
        |> Map.put_new(:lull, @default_lull)
        |> Map.put_new(:arg, nil)
      )

  @impl GenServer
  def init(opts) do
    schedule_work(opts.timeout)
    {:ok, opts}
  end

  @impl GenServer
  def handle_info(:work, state) do
    %{manager: manager, id: id, arg: arg, timeout: timeout, lull: lull} = state

    case manager.perform(id, arg) do
      :halt ->
        Tarearbol.InternalWorker.del(manager.internal_worker_module(), id)
        {:noreply, state}

      result ->
        st = manager.state_module().get(id)
        manager.state_module().put(id, %{st | value: result})
        schedule_work(timeout)
        {:noreply, state, round(timeout * lull)}
    end
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    state.manager.handle_timeout(state)
    {:noreply, state}
  end

  @spec schedule_work(timeout :: non_neg_integer()) :: reference()
  defp schedule_work(timeout), do: Process.send_after(self(), :work, timeout)
end
