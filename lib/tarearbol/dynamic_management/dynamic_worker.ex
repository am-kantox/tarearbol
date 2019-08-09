defmodule Tarearbol.DynamicWorker do
  use GenServer

  def start_link(runner: runner),
    do: GenServer.start_link(__MODULE__, runner: runner)

  @impl GenServer
  def init(opts) do
    schedule_work()
    {:ok, opts}
  end

  @impl GenServer
  def handle_info(:work, [runner: runner] = state) do
    case runner do
      {m, f, a} -> apply(m, f, a)
      {m, f} -> apply(m, f, [])
      m when is_atom(m) -> apply(m, :runner, [])
      fun when is_function(fun, 0) -> fun.()
    end

    schedule_work()
    {:noreply, state}
  end

  defp schedule_work do
    # In a seconds
    Process.send_after(self(), :work, 1_000)
  end
end
