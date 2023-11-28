defmodule Tarearbol.StateSupervisor do
  @moduledoc false

  defmodule Hunter do
    @moduledoc false
    use GenServer

    def start_link(name: name), do: GenServer.start(__MODULE__, [name: name], name: name)

    @impl GenServer
    def init(opts), do: {:ok, opts}

    @impl GenServer
    def handle_cast(:restart!, name: name),
      do: raise("💥 → Planned `Tarearbol` state [#{inspect(name)}] restart")
  end

  use Supervisor

  def start_link(opts) do
    {state_module_spec, opts} = Keyword.pop!(opts, :state_module_spec)
    {name, []} = Keyword.pop!(opts, :name)
    Supervisor.start_link(__MODULE__, {state_module_spec, name}, [])
  end

  @impl Supervisor
  def init({state_module_spec, name}) do
    children = [
      {Hunter, [name: name]},
      state_module_spec
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
