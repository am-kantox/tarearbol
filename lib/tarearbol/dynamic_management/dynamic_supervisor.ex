defmodule Tarearbol.DynamicSupervisor do
  @moduledoc false
  use DynamicSupervisor

  @spec start_link(opts :: keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    {manager, opts} = Keyword.pop(opts, :manager)
    DynamicSupervisor.start_link(__MODULE__, opts, name: manager.dynamic_supervisor_module())
  end

  @impl DynamicSupervisor
  def init(opts),
    do: DynamicSupervisor.init(Keyword.merge([strategy: :one_for_one], opts))
end
