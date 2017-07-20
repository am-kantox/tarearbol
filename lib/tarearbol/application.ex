defmodule Tarearbol.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    # List all child processes to be supervised
    children = [
      supervisor(Task.Supervisor, [[name: Tarearbol.Application]])
      # {Tarearbol.Worker, arg},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tarearbol.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def children do
    Task.Supervisor.children(Tarearbol.Application)
  end

  def kill(child) when is_pid(child) do
    do_kill(Enum.member?(Tarearbol.Application.children(), child), child)
  end

  def task!(job) do
    Task.Supervisor.async_nolink(Tarearbol.Application, job)
  end

  ##############################################################################

  defp do_kill(true, child) do
    Task.Supervisor.terminate_child(Tarearbol.Application, child)
  end

  defp do_kill(false, child) do
    with :ok <- do_kill(true, child), do: {:error, :dead}
  end
end
