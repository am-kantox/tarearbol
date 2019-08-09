defmodule Tarearbol.DynamicWorker do
  @moduledoc false
  use GenServer

  def start_link(id: id, runner: runner),
    do: GenServer.start_link(__MODULE__, id: id, runner: runner)

  @impl GenServer
  def init(opts) do
    schedule_work()
    {:ok, opts}
  end

  @impl GenServer
  def handle_info(:work, [id: id, runner: runner] = state) do
    runner
    |> case do
      {m, f, a} -> apply(m, f, [id | a])
      {m, f} -> apply(m, f, [id])
      m when is_atom(m) -> apply(m, :runner, [id])
      fun when is_function(fun, 1) -> fun.(id)
    end
    |> case do
      :halt ->
        Tarearbol.InternalWorker.del(id)
        {:noreply, state}

      result ->
        updated =
          id
          |> Tarearbol.DynamicManager.State.get(%{})
          |> Map.put(:value, result)

        Tarearbol.DynamicManager.State.put(id, updated)

        schedule_work()
        {:noreply, state}
    end
  end

  defp schedule_work do
    # In a seconds
    Process.send_after(self(), :work, 1_000)
  end
end
