defmodule Tarearbol.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    # List all child processes to be supervised
    children = [
      supervisor(Task.Supervisor, [[name: Tarearbol.Application]]),
      worker(Tarearbol.Cron, [])
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tarearbol.Supervisor]
    Supervisor.start_link(children, opts)
  end

  ##############################################################################

  def children do
    Task.Supervisor.children(Tarearbol.Application)
  end

  def jobs do
    Tarearbol.Application.children()
    |> Enum.map(&Process.info(&1, :dictionary))
    |> Enum.map(fn {:dictionary, dict} -> dict[:job] end)
    |> Enum.filter(& &1)
  end

  def kill(), do: for(child <- children(), do: kill(child))

  def kill(child) when is_pid(child) do
    Tarearbol.Application.children()
    |> Enum.member?(child)
    |> do_kill(child)
  end

  def task!(job) when is_function(job, 0) do
    Task.Supervisor.async_nolink(Tarearbol.Application, job)
  end

  def task!({mod, fun, params}) do
    Task.Supervisor.async_nolink(Tarearbol.Application, mod, fun, params)
  end

  ##############################################################################

  defp do_kill(true, child) do
    Task.Supervisor.terminate_child(Tarearbol.Application, child)
  end

  defp do_kill(false, child) do
    with :ok <- do_kill(true, child), do: {:error, :dead}
  end
end
