defmodule Tarearbol.DynamicSupervisor do
  @moduledoc false

  use Boundary

  use DynamicSupervisor

  @spec start_link(opts :: keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    {manager, opts} = Keyword.pop(opts, :manager)
    DynamicSupervisor.start_link(__MODULE__, opts, name: manager.__dynamic_supervisor_module__())
  end

  @impl DynamicSupervisor
  def init(opts),
    do: DynamicSupervisor.init(Keyword.merge([strategy: :one_for_one], opts))
end
