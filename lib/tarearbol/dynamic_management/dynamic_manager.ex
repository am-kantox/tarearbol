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
          for i <- 1..10, do: {"foo_#{i}", []}, into: %{}
        end
      end

      {:ok, pid} = DynamicManager.start_link()

  The above would spawn `10` children with IDs `"foo_1".."foo_10"`.

  ---

  `DynamicManager` also allows dynamic workers management. It exports three
  functions

      @spec put(id :: id(), opts :: Enum.t()) :: pid()
      @spec del(id :: id()) :: :ok
      @spec get(id :: id()) :: Enum.t()

  The semantics of `put/2` arguments is the same as a single `child_spec`,
  `del/1` and `get/1` receive the unique ID of the child and shutdown it or
  return it’s payload respectively.

  """
  @moduledoc since: "0.9.0"

  use Boundary, exports: [Child]

  @typedoc "Identifier of the child process"
  @type id :: any()

  @typedoc "Payload associated with the worker"
  @type payload :: any()

  @typedoc "Expected response from the `DymanicManager` implementation"
  @type response ::
          :halt
          | {:replace, payload()}
          | {:replace, id(), payload()}
          | {{:timeout, integer()}, payload()}
          | {:ok, any()}
          | any()

  @doc """
  This function is called to retrieve the map of children with name as key
  and a workers as the value.

  The value must be an enumerable with keys among:
  - `:payload` (passed as second argument to `perform/2`, default `nil`)
  - `:timeout` (time between iterations of `perform/2`, default `1` second)
  - `:lull` (threshold to notify latency in performing, default `1.1` (the threshold is `:lull` times the `:timeout`))

  This function should not care about anything save for producing side effects.

  It will be backed by `DynamicSupervisor`. The value it returns will be put
  into the state under `children` key.
  """
  @doc since: "0.9.0"
  @callback children_specs :: %{required(id()) => Enum.t()}

  @doc """
  The main function, doing all the job, supervised.

  It will be called with the child `id` as first argument and the
  `payload` option to child spec as second argument (defaulting to nil,
  can also be ignored if not needed).

  ### Return values

  `perform/2` might return

  - `:halt` if it wants to be killed
  - `{:ok, result}` to store the last result and reschedule with default timeout
  - `{:replace, id, payload}` to replace the current worker with the new one
  - `{{:timeout, timeout}, result}` to store the last result and reschedule in given timeout interval
  - or **_deprecated_** anything else will be treated as a result
  """
  @doc since: "0.9.0"
  @callback perform(id :: id(), payload :: payload()) :: response()

  @doc """
  The method to implement for explicit `GenServer.call/3` on the wrapping worker.
  """
  @doc since: "1.2.0"
  @callback call(message :: any(), from :: GenServer.from(), {id :: id(), payload :: payload()}) ::
              response()

  @doc """
  The method to implement for explicit `GenServer.cast/2` on the wrapping worker.
  """
  @doc since: "1.2.1"
  @callback cast(message :: any(), {id :: id(), payload :: payload()}) :: response()

  @doc """
  The method that will be called before the worker is terminated.
  """
  @doc since: "1.2.0"
  @callback terminate(reason :: term(), {id :: id(), payload :: payload()}) :: any()

  @doc """
  Declares an instance-wide callback to report state; if the startup process
  takes a while, it’d be run in `handle_continue/2` and this function will be
  called after it finishes so that the application might start using it.

  If the application is not interested in receiving state updates, e. g. when
  all it needs from runners is a side effect, there is a default implementation
  that does nothing.
  """
  @doc since: "0.9.0"
  @callback handle_state_change(state :: :down | :up | :starting | :unknown) :: :ok | :restart

  @doc """
  Declares a callback to report slow process (when the scheduler cannot process
  in a reasonable time).
  """
  @doc since: "0.9.5"
  @callback handle_timeout(state :: map()) :: any()

  defmodule Child do
    @moduledoc false
    @type t :: %{
            __struct__: __MODULE__,
            pid: pid(),
            value: Tarearbol.DynamicManager.payload(),
            busy?: nil | DateTime.t(),
            opts: keyword()
          }
    @enforce_keys [:pid, :value]
    defstruct [:pid, :value, :opts, :busy?]
  end

  @doc false
  defmacro __using__(opts) do
    {continue, opts} = Keyword.pop(opts, :continue)
    {distributed, opts} = Keyword.pop(opts, :distributed)

    quote generated: true, location: :keep do
      @namespace Keyword.get(unquote(opts), :namespace, __MODULE__)

      @doc false
      @spec namespace :: module()
      def namespace, do: @namespace

      @continue_handler (case unquote(continue) do
                           nil ->
                             nil

                           fun when is_function(fun, 0) ->
                             fun

                           fun when is_function(fun, 1) ->
                             fun

                           fun when is_function(fun, 2) ->
                             fun

                           {mod, fun, arity}
                           when is_atom(mod) and is_atom(fun) and arity in [0, 1, 2] ->
                             Function.capture(mod, fun, arity)

                           {mod, fun} when is_atom(mod) and is_atom(fun) ->
                             Function.capture(mod, fun, 1)

                           mod when is_atom(mod) ->
                             Function.capture(mod, :continue, 1)
                         end)

      @doc false
      @spec continue_handler ::
              nil | (Tarearbol.DynamicManager.payload() -> Tarearbol.DynamicManager.payload())
      def continue_handler, do: @continue_handler

      @spec child_mod(module :: module() | list()) :: module()
      defp child_mod(module) when is_atom(module), do: child_mod(Module.split(module))

      defp child_mod(module) when is_list(module),
        do: Module.concat(@namespace, List.last(module))

      @doc false
      @spec internal_worker_module :: module()
      def internal_worker_module, do: child_mod(Tarearbol.InternalWorker)

      @doc false
      @spec dynamic_supervisor_module :: module()
      def dynamic_supervisor_module, do: child_mod(Tarearbol.DynamicSupervisor)

      state_module_ast =
        quote generated: true, location: :keep do
          @moduledoc false
          use GenServer

          alias Tarearbol.DynamicManager

          defstruct state: :down, children: %{}, manager: nil

          @type t :: %{
                  __struct__: __MODULE__,
                  state: :down | :up | :starting | :unknown,
                  children: %{optional(DynamicManager.id()) => DynamicManager.Child.t()},
                  manager: module()
                }

          @spec start_link([{:manager, atom()}]) :: GenServer.on_start()
          def start_link(manager: manager),
            do: GenServer.start_link(__MODULE__, [manager: manager], name: __MODULE__)

          @spec state :: t()
          def state, do: GenServer.call(__MODULE__, :state)

          @spec update_state(state :: :down | :up | :starting | :unknown) :: :ok
          def update_state(state), do: GenServer.cast(__MODULE__, {:update_state, state})

          @spec put(id :: DynamicManager.id(), props :: map() | keyword()) :: :ok
          def put(id, props), do: GenServer.cast(__MODULE__, {:put, id, props})

          @spec del(id :: DynamicManager.id()) :: :ok
          def del(id), do: GenServer.cast(__MODULE__, {:del, id})

          @spec get(id :: DynamicManager.id()) :: :ok
          def get(id, default \\ nil),
            do: GenServer.call(__MODULE__, {:get, id, default})

          @impl GenServer
          def init(opts) do
            state = struct(__MODULE__, Keyword.put(opts, :state, :starting))

            state.manager.handle_state_change(:starting)
            {:ok, state}
          end

          @impl GenServer
          def handle_call(:state, _from, %__MODULE__{} = state),
            do: {:reply, state, state}

          @impl GenServer
          def handle_call(
                {:get, id, default},
                _from,
                %__MODULE__{children: children} = state
              ),
              do: {:reply, Map.get(children, id, default), state}

          @impl GenServer
          def handle_cast(
                {:put, id, %DynamicManager.Child{} = props},
                %__MODULE__{children: children} = state
              ),
              do: {:noreply, %{state | children: Map.put(children, id, props)}}

          @impl GenServer
          def handle_cast({:put, id, props}, %__MODULE__{} = state),
            do: handle_cast({:put, id, struct(DynamicManager.Child, props)}, state)

          @impl GenServer
          def handle_cast({:del, id}, %__MODULE__{children: children} = state),
            do: {:noreply, %{state | children: Map.delete(children, id)}}

          @impl GenServer
          def handle_cast({:update_state, new_state}, %__MODULE__{} = state),
            do: {:noreply, %{state | state: new_state}}
        end

      @state_module Module.concat(@namespace, State)
      Module.create(@state_module, state_module_ast, __ENV__)

      @doc false
      @spec state_module :: module()
      def state_module, do: @state_module

      @doc false
      @spec state :: struct()
      def state, do: @state_module.state()

      @doc false
      @spec free :: %Stream{}
      def free, do: Stream.filter(state().children, &is_nil(elem(&1, 1).busy?))

      @registry_module Module.concat(@namespace, Registry)

      @doc false
      @spec registry_module :: module()
      def registry_module, do: @registry_module

      require Logger

      @behaviour Tarearbol.DynamicManager

      @impl Tarearbol.DynamicManager
      def perform(id, _payload) do
        Logger.warn(
          "perform for id[#{id}] was executed with state\n\n" <>
            inspect(state_module().state()) <>
            "\n\nyou want to override `perform/2` in your #{inspect(__MODULE__)}\n" <>
            "to perform some actual work instead of printing this message"
        )

        if Enum.random(1..3) == 1, do: :halt, else: {:ok, 42}
      end

      @impl Tarearbol.DynamicManager
      def call(_message, _from, {id, _payload}) do
        Logger.warn(
          "call for id[#{id}] was executed with state\n\n" <>
            inspect(state_module().state()) <>
            "\n\nyou want to override `call/3` in your #{inspect(__MODULE__)}\n" <>
            "to perform some actual work instead of printing this message"
        )

        :ok
      end

      @impl Tarearbol.DynamicManager
      def cast(_message, {id, _payload}) do
        Logger.warn(
          "cast for id[#{id}] was executed with state\n\n" <>
            inspect(state_module().state()) <>
            "\n\nyou want to override `cast/2` in your #{inspect(__MODULE__)}\n" <>
            "to perform some actual work instead of printing this message"
        )

        :ok
      end

      @impl Tarearbol.DynamicManager
      def terminate(reason, {id, payload}) do
        Logger.info(
          "Exiting DynamicWorker[" <>
            inspect(id) <>
            "] with reason " <> inspect(reason) <> ". Payload: " <> inspect(payload)
        )
      end

      defoverridable perform: 2, call: 3, cast: 2, terminate: 2

      @impl Tarearbol.DynamicManager
      def handle_state_change(state),
        do: Logger.info("[#{inspect(__MODULE__)}] state has changed to #{state}")

      defoverridable handle_state_change: 1

      @impl Tarearbol.DynamicManager
      def handle_timeout(state), do: Logger.warn("A worker is too slow [#{inspect(state)}]")

      defoverridable handle_timeout: 1

      use Supervisor

      @doc """
      Starts the `DynamicSupervisor` and its helpers to manage dynamic children
      """
      def start_link(opts \\ []),
        do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

      @impl Supervisor
      def init(opts) do
        children = [
          {Registry, [keys: :unique, name: @registry_module]},
          {@state_module, [manager: __MODULE__]},
          {Tarearbol.DynamicSupervisor, Keyword.put(opts, :manager, __MODULE__)},
          {Tarearbol.InternalWorker, [manager: __MODULE__]}
        ]

        Logger.info(
          "Starting #{inspect(__MODULE__)} with following children:\n" <>
            "    State → #{inspect(@state_module)}\n" <>
            "    DynamicSupervisor → #{inspect(dynamic_supervisor_module())}\n" <>
            "    InternalWorker → #{inspect(internal_worker_module())}"
        )

        Supervisor.init(children, strategy: :rest_for_one)
      end

      @doc """
      Performs a `GenServer.call/3` to the worker specified by `id`.

      `c:Tarearbol.DynamicManager.call/3` callback should be implemented for this to work.
      """
      @doc since: "1.2.0"
      @spec synch_call(id :: nil | Tarearbol.DynamicManager.id(), message :: any()) ::
              {:ok, any()} | :error
      def synch_call(nil, message) do
        free()
        |> Enum.take(1)
        |> case do
          [] -> :error
          [{_id, %Child{pid: pid}}] -> {:ok, GenServer.call(pid, message)}
        end
      end

      def synch_call(id, message) do
        case Registry.lookup(@registry_module, id) do
          [{pid, nil}] -> {:ok, GenServer.call(pid, message)}
          [] -> :error
        end
      end

      @doc """
      Performs a `GenServer.cast/2` to the worker specified by `id`.

      `c:Tarearbol.DynamicManager.cast/2` callback should be implemented for this to work.
      """
      @doc since: "1.2.1"
      @spec asynch_call(id :: nil | Tarearbol.DynamicManager.id(), message :: any()) ::
              :ok | :error
      def asynch_call(nil, message) do
        free()
        |> Enum.take(1)
        |> case do
          [] -> :error
          [{_id, %Child{pid: pid}}] -> GenServer.cast(pid, message)
        end
      end

      def asynch_call(id, message) do
        case Registry.lookup(@registry_module, id) do
          [{pid, nil}] -> GenServer.cast(pid, message)
          [] -> :error
        end
      end

      @put if unquote(distributed), do: :multiput, else: :put
      @doc """
      Dynamically adds a supervised worker implementing `Tarearbol.DynamicManager`
        behaviour to the list of supervised children.

      If `distributed: true` parameter was given to `use Tarearbol.DynamicManager`,
        puts the worker into all the nodes managed by `Cloister`. `:cloister` dependency
        must be added to a project to use this feature.
      """
      def put(id, opts),
        do: apply(Tarearbol.InternalWorker, @put, [internal_worker_module(), id, opts])

      @doc """
      Dynamically adds a supervised worker implementing `Tarearbol.DynamicManager`
        behaviour to the list of supervised children on all the nodes managed by `Cloister`.

      Use `distributed: true` parameter in call to `use Tarearbol.DynamicManager`
        and regular `put/2` instead.
      """
      @doc deprecated: """
           Use `distributed: true` parameter in call to `use Tarearbol.DynamicManager`
             and regular `put/2` instead.
           """
      defdelegate multiput(id, opts), to: __MODULE__, as: :put

      @del if unquote(distributed), do: :multidel, else: :del
      @doc """
      Dynamically removes a supervised worker implementing `Tarearbol.DynamicManager`
      behaviour from the list of supervised children

      If `distributed: true` parameter was given to `use Tarearbol.DynamicManager`,
        deletes the worker from all the nodes managed by `Cloister`. `:cloister` dependency
        must be added to a project to use this feature.
      """
      def del(id),
        do: apply(Tarearbol.InternalWorker, @del, [internal_worker_module(), id])

      @doc """
      Dynamically removes a supervised worker implementing `Tarearbol.DynamicManager`
        behaviour from the list of supervised children on all the nodes managed by `Cloister`.

      Use `distributed: true` parameter in call to `use Tarearbol.DynamicManager`
        and regular `del/1` instead.
      """
      @doc deprecated: """
           Use `distributed: true` parameter in call to `use Tarearbol.DynamicManager`
             and regular `del/1` instead.
           """
      defdelegate multidel(id), to: __MODULE__, as: :del

      @doc """
      Retrieves the information (`payload`, `timeout`, `lull` etc.) assotiated with
      the supervised worker
      """
      def get(id), do: Tarearbol.InternalWorker.get(internal_worker_module(), id)

      @doc """
      Restarts the `DynamicManager` to the clean state
      """
      def restart, do: Tarearbol.InternalWorker.restart(internal_worker_module())
    end
  end
end
