defmodule Tarearbol.Application do
  @moduledoc false

  use Boundary

  use Application

  @spec start(Application.app(), Application.restart_type()) ::
          {:error, any()} | {:ok, pid()} | {:ok, pid(), any()}
  def start(_type, _args) do
    children = [
      {Task.Supervisor, [name: Tarearbol.Application]}
      # {Tarearbol.Metronome, []}
    ]

    opts = [strategy: :one_for_one, name: Tarearbol.Supervisor]
    Supervisor.start_link(children, opts)
  end

  ##############################################################################

  @spec children :: [pid()]
  def children, do: Task.Supervisor.children(Tarearbol.Application)

  def jobs do
    children()
    |> Enum.map(&Process.info(&1, :dictionary))
    |> Enum.map(fn {:dictionary, dict} -> dict[:job] end)
    |> Enum.reject(&is_nil/1)
  end

  @spec kill :: [:ok | {:error, :not_found | :dead}]
  def kill, do: for(child <- children(), do: kill(child))

  @spec kill(pid()) :: :ok | {:error, :not_found | :dead}
  def kill(child) when is_pid(child) do
    children()
    |> Enum.member?(child)
    |> do_kill(child)
  end

  @spec task!((() -> any()) | {module(), atom(), list()}) :: Task.t()
  def task!(job) when is_function(job, 0),
    do: Task.Supervisor.async_nolink(Tarearbol.Application, job)

  def task!({mod, fun, params}) do
    Task.Supervisor.async_nolink(Tarearbol.Application, mod, fun, params)
  end

  ##############################################################################

  @spec do_kill(boolean(), pid()) :: :ok | {:error, :not_found | :dead}
  defp do_kill(true, child),
    do: Task.Supervisor.terminate_child(Tarearbol.Application, child)

  defp do_kill(false, child),
    do: with(:ok <- do_kill(true, child), do: {:error, :dead})
end
