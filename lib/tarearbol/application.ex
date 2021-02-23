defmodule Tarearbol.Application do
  @moduledoc false

  use Boundary, deps: [Tarearbol.Scheduler, Tarearbol.DynamicManager]

  use Application

  @spec start(Application.app(), Application.restart_type()) ::
          {:error, any()} | {:ok, pid()} | {:ok, pid(), any()}
  def start(_type, _args) do
    optional =
      if Application.get_env(:tarearbol, :scheduler, false), do: [Tarearbol.Scheduler], else: []

    children = [
      {Task.Supervisor, [name: Tarearbol.Application]} | optional
    ]

    opts = [strategy: :one_for_one, name: Tarearbol.Supervisor]
    Supervisor.start_link(children, opts)
  end

  ##############################################################################

  @spec children :: [{:local | :external, Process.dest(), Tarearbol.Scheduler.Job.t(), keyword()}]
  def children, do: children(:local) ++ children(:external)

  @spec children(:local | :external) :: [
          {:local | :external, Process.dest(), Tarearbol.Scheduler.Job.t(), keyword()}
        ]
  def children(:local) do
    Tarearbol.Application
    |> Task.Supervisor.children()
    |> Enum.map(&{:local, &1, Process.info(&1, :dictionary)})
    |> Enum.map(fn {:local, pid, {:dictionary, dict}} -> {:local, pid, dict[:job]} end)
    |> Enum.map(fn
      {:local, pid, {job, interval, opts}} ->
        {:local, pid, job, Keyword.put(opts, :timeout, interval)}

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  def children(:external) do
    for {name, %Tarearbol.DynamicManager.Child{} = child} <-
          Tarearbol.Scheduler.State.state().children do
      {:external, child.pid, child.opts.payload.job,
       [__name__: name, timeout: child.opts.timeout]}
    end
  end

  def jobs, do: Enum.map(children(), &elem(&1, 2))

  @spec kill :: [:ok | {:error, :not_found | :dead}]
  def kill, do: for(child <- children(), do: kill(child))

  @spec kill(Process.dest()) :: :ok | {:error, :not_found | :dead}
  def kill(child) when is_pid(child) or is_port(child) or is_atom(child) or is_tuple(child) do
    child =
      case child do
        {_, pid, _, _} -> pid
        pid -> pid
      end

    case Enum.find(children(), &match?({_, ^child, _, _}, &1)) do
      nil -> {:error, :not_found}
      {:local, victim, _, _} -> Task.Supervisor.terminate_child(Tarearbol.Application, victim)
      {:external, _, _, opts} -> Tarearbol.Scheduler.del(opts[:__name__])
    end
  end

  @spec task!((() -> any()) | {module(), atom(), list()}) :: Task.t()
  def task!(job) when is_function(job, 0),
    do: Task.Supervisor.async_nolink(Tarearbol.Application, job)

  def task!({mod, fun, params}),
    do: Task.Supervisor.async_nolink(Tarearbol.Application, mod, fun, params)
end
