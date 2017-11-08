defmodule Tarearbol.Cron do
  @moduledoc false

  use GenServer
  require Logger

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:ok, table} = :dets.open_file(:tarearbol, [type: :set])
    table
    |> tasks!()
    |> Enum.each(fn {{m, f, a}, t, o} ->
         Tarearbol.Errand.run_at({m, f, a}, t, o)
       end)
    {:ok, table}
  end

  def terminate(_reason, table), do: :dets.close(table)

  #############################################################################

  def jobs(), do: GenServer.call(__MODULE__, :tasks)

  def clear!(), do: GenServer.call(__MODULE__, :clear)

  def put_task({{_mod, _fun, _args}, _time, _opts} = task),
    do: GenServer.call(__MODULE__, {:put_task, task})

  def put_task({fun, _time, _opts} = task) when is_function(fun),
    do: GenServer.call(__MODULE__, {:not_supported, task})

  def del_task({{_mod, _fun, _args}, _time, _opts} = task),
    do: GenServer.call(__MODULE__, {:del_task, task})

  def del_task({fun, _time, _opts} = task) when is_function(fun),
    do: GenServer.call(__MODULE__, {:not_supported, task})

  #############################################################################

  def handle_call(:tasks, _from, table),
    do: {:reply, tasks!(table), table}

  def handle_call(:clear, _from, table) do
    cleared = tasks!(table)
    :dets.insert(table, {:tasks, []})
    {:reply, cleared, table}
  end

  def handle_call({:not_supported, task}, _from, table) do
    Logger.error("Inplace functions are not supported. Got [#{inspect task}].")
    {:reply, task, table}
  end

  def handle_call({:put_task, {{_mod, _fun, _args}, _time, _opts} = task}, _from, table) do
    reply = [task | do_delete(task, table)]
    :dets.insert(table, {:tasks, reply})
    {:reply, reply, table}
  end

  def handle_call({:del_task, {{_mod, _fun, _args}, _time, _opts} = task}, _from, table) do
    reply = do_delete(task, table)
    :dets.insert(table, {:tasks, reply})
    {:reply, reply, table}
  end

  #############################################################################

  defp do_delete({{mod, fun, args}, time, opts}, table) do
    table
    |> tasks!()
    |> Enum.filter(fn {{m, f, a}, t, o} ->
         DateTime.diff(t, time, :microsecond) >= 1_000 ||
           m != mod || f != fun || a != args ||
           Enum.sort(o) != Enum.sort(opts)
       end)
  end

  # FIXME [AM] REFACTOR
  defp tasks!(table) do
    case :dets.lookup(table, :tasks) do
      {:error, _reason} ->
        :dets.insert(table, {:tasks, []})
        []
      [] ->
        :dets.insert(table, {:tasks, []})
        []
      tasks -> tasks[:tasks]
    end
  end
end
