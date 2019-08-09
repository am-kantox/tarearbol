defmodule Tarearbol.DynamicManager do
  @moduledoc ~S"""
  The scaffold implementation to dynamically manage many similar tasks running
  as processes.

  It creates a main supervisor, managing the `GenServer` holding the state and
  `DynamicSupervisor` handling chidren. It has a strategy `:rest_for_one`,
  assuming that if the process holding the state crashes, the children will be
  restarted.

  Typically one calls `use Tarearbol.DynamicManager` and implements at least
  `children_specs/0` callback and receives back supervised tree with a state
  and many processes controlled by `DynamicSupervisor`.

  To see how it works you might try

      defmodule DynamicManager do
        use Tarearbol.DynamicManager

        def children_specs do
          for i <- 1..10, do: {"foo_#{i}", DynamicManager}, into: %{}
        end
      end

      {:ok, pid} = DynamicManager.start_link()
  """
  @moduledoc since: "0.9.0"

  @doc """
  This function is called to retrieve the map of children with name as key
  and a workers as the value. Optionally the value might be `{m, f, a}` or
  `{m, f}`, or just `m` (the function name is assumed to be `:runner`) or
  even a plain anonymous function of zrity zero.

  This function should not care about anything save for producing side effects.

  It will be backed by `DynamicSupervisor`. The value it returns will be put
  into the state under `children` key.
  """
  @doc since: "0.9.0"
  @callback children_specs :: %{
              required(binary()) =>
                {module(), function(), list()} | {module(), function()} | module() | (() -> any())
            }

  @doc """
  The main function, doing all the job, supervised. This function will be used
  for children specs without `module()` given. Convenience function when most
  of or even all the children have the similar behaviour.

  For instance, if one has forty two HTTP sources to get similar data from,
  this function might be implemented instead of passing the same module many
  times in call to `children_specs/0`.

  Has default overridable implementation, which is a noop for those who manage
  all the children manually.
  """
  @doc since: "0.9.0"
  @callback runner :: any()

  @doc """
  Declares an instance-wide callback to report state; if the startup process
  takes a while, it’d be run in `handle_continue/2` and this function will be
  called after it finishes so that the application might start using it.

  If the application is not interested in receiving state updates, e. g. when
  all it needs from runners is a side effect, there is a default implementation
  that does nothing.
  """
  @doc since: "0.9.0"
  @callback on_state_change(state :: :down | :up | :starting | :unknown) :: :ok | :restart

  defmodule State do
    @moduledoc false
    use GenServer

    defstruct state: :down, children: %{}, manager: nil

    @type t :: %{}

    def start_link(manager: mod),
      do: GenServer.start_link(__MODULE__, [manager: mod], name: __MODULE__)

    @spec state :: State.t()
    def state(), do: GenServer.call(__MODULE__, :state)

    @spec update_state(state :: :down | :up | :starting | :unknown) :: :ok
    def update_state(state), do: GenServer.cast(__MODULE__, {:update_state, state})

    @spec put(id :: binary(), props :: map()) :: :ok
    def put(id, props), do: GenServer.cast(__MODULE__, {:put, id, props})

    @spec del(id :: binary()) :: :ok
    def del(id), do: GenServer.cast(__MODULE__, {:del, id})

    @spec get(id :: binary()) :: :ok
    def get(id, default \\ nil), do: GenServer.call(__MODULE__, {:get, id, default})

    @impl GenServer
    def init(opts) do
      state = struct(Tarearbol.DynamicManager.State, Keyword.put(opts, :state, :starting))
      state.manager.on_state_change(:starting)
      {:ok, state}
    end

    @impl GenServer
    def handle_call(:state, _from, %__MODULE__{} = state),
      do: {:reply, state, state}

    @impl GenServer
    def handle_call({:get, id, default}, _from, %__MODULE__{children: children} = state),
      do: {:reply, Map.get(children, id, default), state}

    @impl GenServer
    def handle_cast({:put, id, props}, %__MODULE__{children: children} = state),
      do: {:noreply, %{state | children: Map.put(children, id, props)}}

    @impl GenServer
    def handle_cast({:del, id}, %__MODULE__{children: children} = state),
      do: {:noreply, %{state | children: Map.delete(children, id)}}

    @impl GenServer
    def handle_cast({:update_state, new_state}, %__MODULE__{} = state),
      do: {:noreply, %{state | state: new_state}}
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      require Logger

      @behaviour Tarearbol.DynamicManager

      @impl Tarearbol.DynamicManager
      def runner(),
        do:
          Logger.warn(
            "runner was executed with state [#{inspect(Tarearbol.DynamicManager.State.state())}]\n" <>
              "you want to override `runner/0` in your #{inspect(__MODULE__)}\n" <>
              "to perform some actual work instead of printing this message"
          )

      defoverridable runner: 0

      @impl Tarearbol.DynamicManager
      def on_state_change(state),
        do: Logger.info("[#{inspect(__MODULE__)}] state has changed to #{state}")

      defoverridable on_state_change: 1

      use Supervisor

      def start_link(opts \\ []),
        do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

      @impl Supervisor
      def init(opts) do
        children = [
          {Tarearbol.DynamicManager.State, [manager: __MODULE__]},
          {Tarearbol.DynamicSupervisor, opts},
          {Tarearbol.InternalWorker, [manager: __MODULE__]}
        ]

        Supervisor.init(children, strategy: :rest_for_one)
      end
    end
  end
end
