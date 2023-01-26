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

  ## Workers Management

  `DynamicManager` allows dynamic workers management. It exports three functions

      @spec get(id :: id()) :: Enum.t()
      @spec put(id :: id(), opts :: Enum.t()) :: pid()
      @spec del(id :: id()) :: :ok
      @spec restart(id :: id()) :: :ok

  The semantics of `put/2` arguments is the same as a single `child_spec`,
  `del/1` and `get/1` receive the unique ID of the child and shutdown it or
  return it’s payload respectively.

  ## Workers Callbacks

  Workers are allowed to implement several callbacks to be used to pass messages
    to them.

  - **`peform/2`** is called periodically by the library internals; the interval
    is set upon worker initialization via `children_specs/1` (static) or `put/2`
    (dynamic); the interval set to `0` suppresses periodic invocations
  - **`call/3`** to handle synchronous message send to worker
  - **`cast/2`** to handle asynchronous message send to worker
  - **`terminate/2`** to handle worker process termination

  All the above should return a value of `t:Tarearbol.DynamicManager.response/0` type.

  Also, the implementing module might use a custom initialization function
    to e. g. dynamically build payload. Is should be passed to `use DynamicManager`
    as a parameter `init: handler` and might be a tuple `{module(), function(), arity()}` or
    a captured function `&MyMod.my_init/1`. Arities 0, 1 and 2 are allowed, as described by
    `t:Tarearbol.DynamicManager.init_handler/0` type.

  The worker process will call this function from `c:GenServer.handle_continue/2` callback.
  """
  @moduledoc since: "0.9.0"

  use Boundary, exports: [Child]
  require Logger

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

  @typedoc "Post-instantion init handler type, that might be passed to `use DynamicManager` vis `init:`"
  @type init_handler ::
          nil
          | (() -> Tarearbol.DynamicManager.payload())
          | (Tarearbol.DynamicManager.payload() -> Tarearbol.DynamicManager.payload())
          | (Tarearbol.DynamicManager.id(), Tarearbol.DynamicManager.payload() ->
               Tarearbol.DynamicManager.payload())

  @doc """
  This function is called to retrieve the map of children with name as key
  and a workers as the value.

  The value must be an enumerable with keys among:
  - `:payload` passed as second argument to `perform/2`, default `nil`
  - `:timeout` time between iterations of `perform/2`, default `1` second
  - `:lull` threshold to notify latency in performing, default `1.1`
    (the threshold is `:lull` times the `:timeout`)

  This function should not care about anything save for producing side effects.

  It will be backed by `DynamicSupervisor`. The value it returns will be put
  into the state under `children` key.
  """
  @doc since: "0.9.0"
  @callback children_specs :: %{required(id()) => Enum.t()}

  @doc """
  The main function, doing all the internal job, supervised.

  It will be called with the child `id` as first argument and the
  `payload` option to child spec as second argument (defaulting to `nil`,
  can also be ignored if not needed).

  ### Return values

  `perform/2` might return

  - `:halt` if it wants to be killed
  - `{:ok, result}` to store the last result and reschedule with default timeout
  - `{:replace, payload}` to replace the payload (state) of the current worker with the new one
  - `{:replace, id, payload}` to replace the current worker with the new one
  - `{{:timeout, timeout}, result}` to store the last result and reschedule in given timeout interval
  - or **_deprecated_** anything else will be treated as a result
  """
  @doc since: "0.9.0"
  @callback perform(id :: id(), payload :: payload()) :: response()

  @doc """
  The method to implement to support explicit `GenServer.call/3` on the wrapping worker.
  """
  @doc since: "1.2.0"
  @callback call(message :: any(), from :: GenServer.from(), {id :: id(), payload :: payload()}) ::
              response()

  @doc """
  The method to implement to support explicit `GenServer.cast/2` on the wrapping worker.
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
    @moduledoc """
    The internal representation of a child process under `DynamicManager` supervision
    """
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

  @defaults [timeout: 1_000, lull: 1.1, payload: nil]

  @doc false
  defmacro __using__(opts) do
    {defaults, opts} = Keyword.pop(opts, :defaults, [])
    defaults = Keyword.merge(@defaults, defaults)

    {init_handler, opts} = Keyword.pop(opts, :init)
    {distributed, opts} = Keyword.pop(opts, :distributed, false)
    {pickup, opts} = Keyword.pop(opts, :pickup, :hashring)

    quote generated: true, location: :keep do
      @on_definition Tarearbol.DynamicManager

      @__namespace__ Keyword.get(unquote(opts), :namespace, __MODULE__)
      @__pickup__ unquote(pickup)
      @__defaults__ for {k, v} <- unquote(defaults), do: {k, Macro.expand(v, __MODULE__)}

      @doc false
      @spec __defaults__ :: %{
              timeout: non_neg_integer(),
              lull: float(),
              payload: term()
            }
      def __defaults__, do: Map.new(@__defaults__)

      @doc false
      @spec __namespace__ :: module()
      def __namespace__, do: @__namespace__

      @init_handler (case unquote(init_handler) do
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
                     end)

      @spec __child_mod__(module :: module() | list()) :: module()
      defp __child_mod__(module) when is_atom(module), do: __child_mod__(Module.split(module))

      defp __child_mod__(module) when is_list(module),
        do: Module.concat(@__namespace__, List.last(module))

      @doc false
      @spec __init_handler__ :: Tarearbol.DynamicManager.init_handler()
      def __init_handler__, do: @init_handler

      @doc false
      @spec __internal_worker_module__ :: module()
      def __internal_worker_module__, do: __child_mod__(Tarearbol.InternalWorker)

      @doc false
      @spec __dynamic_supervisor_module__ :: module()
      def __dynamic_supervisor_module__, do: __child_mod__(Tarearbol.DynamicSupervisor)

      state_module_ast =
        quote generated: true, location: :keep do
          @moduledoc false
          use GenServer

          alias Tarearbol.DynamicManager

          @type t :: %{
                  __struct__: __MODULE__,
                  state: :down | :up | :starting | :unknown,
                  children: %{optional(DynamicManager.id()) => DynamicManager.Child.t()},
                  manager: module(),
                  ring: HashRing.t()
                }

          defstruct [:manager, :ring, state: :down, children: %{}]

          @spec start_link([{:manager, atom()}]) :: GenServer.on_start()
          def start_link(manager: manager),
            do: GenServer.start_link(__MODULE__, [manager: manager], name: __MODULE__)

          @spec state :: t()
          def state, do: GenServer.call(__MODULE__, :state)

          @spec update_state(state :: :down | :up | :starting | :unknown) :: :ok
          def update_state(state), do: GenServer.cast(__MODULE__, {:update_state, state})

          @spec put(id :: DynamicManager.id(), props :: map() | keyword()) :: :ok
          def put(id, props), do: GenServer.cast(__MODULE__, {:put, id, props})

          @spec update!(
                  id :: DynamicManager.id(),
                  (DynamicManager.Child.t() -> DynamicManager.Child.t())
                ) :: :ok
          def update!(id, fun), do: GenServer.cast(__MODULE__, {:update!, id, fun})

          @spec del(id :: DynamicManager.id()) :: :ok
          def del(id), do: GenServer.cast(__MODULE__, {:del, id})

          @spec get(id :: DynamicManager.id()) :: DynamicManager.Child.t()
          def get(id, default \\ nil),
            do: GenServer.call(__MODULE__, {:get, id, default})

          @impl GenServer
          def init(opts) do
            opts =
              opts
              |> Keyword.put(:state, :starting)
              |> Keyword.put_new(:ring, HashRing.new())

            state = struct!(__MODULE__, opts)

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
                %__MODULE__{ring: ring, children: children} = state
              ),
              do:
                {:noreply,
                 %{
                   state
                   | ring: ring && HashRing.add_node(ring, id),
                     children: Map.put(children, id, props)
                 }}

          @impl GenServer
          def handle_cast({:put, id, props}, %__MODULE__{} = state),
            do: handle_cast({:put, id, struct(DynamicManager.Child, props)}, state)

          @impl GenServer
          def handle_cast({:update!, id, fun}, %__MODULE__{children: children} = state)
              when is_map_key(children, id),
              do: {:noreply, %{state | children: Map.update!(children, id, fun)}}

          def handle_cast({:update!, _id, _fun}, %__MODULE__{} = state),
            do: {:noreply, state}

          @impl GenServer
          def handle_cast({:del, id}, %__MODULE__{ring: ring, children: children} = state),
            do:
              {:noreply,
               %{
                 state
                 | ring: ring && HashRing.remove_node(ring, id),
                   children: Map.delete(children, id)
               }}

          @impl GenServer
          def handle_cast({:update_state, new_state}, %__MODULE__{} = state),
            do: {:noreply, %{state | state: new_state}}
        end

      @state_module Module.concat(@__namespace__, State)
      Module.create(@state_module, state_module_ast, __ENV__)

      @doc false
      @spec __state_module__ :: module()
      def __state_module__, do: @state_module

      @registry_module Module.concat(@__namespace__, Registry)

      @doc false
      @spec __registry_module__ :: module()
      def __registry_module__, do: @registry_module

      @doc false
      @spec state :: struct()
      def state, do: @state_module.state()

      @doc false
      @spec __free_worker__(kind :: :random | :stream | :hashring, tuple()) ::
              {:id, Tarearbol.DynamicManager.id()} | list()
      def __free_worker__(kind \\ @__pickup__, tuple)

      def __free_worker__(:stream, _tuple),
        do: state().children |> Stream.filter(&is_nil(elem(&1, 1).busy?)) |> Enum.take(1)

      def __free_worker__(:random, _tuple) do
        state().children
        |> Enum.filter(&is_nil(elem(&1, 1).busy?))
        |> case do
          [] -> nil
          [one] -> one
          many -> Enum.random(many)
        end
        |> List.wrap()
      end

      def __free_worker__(:hashring, tuple),
        do: {:id, HashRing.key_to_node(state().ring, tuple)}

      require Logger

      @behaviour Tarearbol.DynamicManager

      @impl Tarearbol.DynamicManager
      def perform(id, _payload) do
        Logger.warn(
          "perform for id[#{id}] was executed with state\n\n" <>
            inspect(__state_module__().state()) <>
            "\n\nyou want to override `perform/2` in your #{inspect(__MODULE__)}\n" <>
            "to perform some actual work instead of printing this message"
        )

        if Enum.random(1..3) == 1, do: :halt, else: {:ok, 42}
      end

      @impl Tarearbol.DynamicManager
      def call(_message, _from, {id, _payload}) do
        Logger.warn(
          "call for id[#{id}] was executed with state\n\n" <>
            inspect(__state_module__().state()) <>
            "\n\nyou want to override `call/3` in your #{inspect(__MODULE__)}\n" <>
            "to perform some actual work instead of printing this message"
        )

        :ok
      end

      @impl Tarearbol.DynamicManager
      def cast(_message, {id, _payload}) do
        Logger.warn(
          "cast for id[#{id}] was executed with state\n\n" <>
            inspect(__state_module__().state()) <>
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
            "    DynamicSupervisor → #{inspect(__dynamic_supervisor_module__())}\n" <>
            "    InternalWorker → #{inspect(__internal_worker_module__())}"
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
      def synch_call(id, message),
        do: do_ynch_call(:call, id, message)

      @doc """
      Performs a `GenServer.cast/2` to the worker specified by `id`.

      `c:Tarearbol.DynamicManager.cast/2` callback should be implemented for this to work.
      """
      @doc since: "1.2.1"
      @spec asynch_call(id :: nil | Tarearbol.DynamicManager.id(), message :: any()) ::
              :ok | :error
      def asynch_call(id, message),
        do: do_ynch_call(:cast, id, message)

      @spec do_ynch_call(:call | :cast, nil | any(), term()) :: :error | :ok | {:ok, term()}
      defp do_ynch_call(type, nil, message) do
        @__pickup__
        |> __free_worker__(message |> Tuple.to_list() |> Enum.take(2) |> List.to_tuple())
        |> case do
          {:id, worker_id} ->
            do_ynch_call(type, worker_id, message)

          [] ->
            :error

          [{_id, %Child{pid: pid}} | _] ->
            GenServer
            |> apply(type, [pid, message])
            |> do_wrap_result(type)
        end
      end

      defp do_ynch_call(type, id, message) do
        case Registry.lookup(@registry_module, id) do
          [{pid, nil}] -> GenServer |> apply(type, [pid, message]) |> do_wrap_result(type)
          [] -> :error
        end
      end

      @spec do_wrap_result(result, :call | :cast) :: {:ok, result} | :ok when result: any()
      defp do_wrap_result(result, :call), do: {:ok, result}
      defp do_wrap_result(result, :cast), do: result

      @put if unquote(distributed), do: :multiput, else: :put
      @doc """
      Dynamically adds a supervised worker implementing `Tarearbol.DynamicManager`
        behaviour to the list of supervised children.

      If `distributed: true` parameter was given to `use Tarearbol.DynamicManager`,
        puts the worker into all the nodes managed by `Cloister`. `:cloister` dependency
        must be added to a project to use this feature.
      """
      def put(id, opts),
        do: apply(Tarearbol.InternalWorker, @put, [__internal_worker_module__(), id, opts])

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
        do: apply(Tarearbol.InternalWorker, @del, [__internal_worker_module__(), id])

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
      def get(id), do: Tarearbol.InternalWorker.get(__internal_worker_module__(), id)

      @doc """
      Restarts the `DynamicManager` to the clean state
      """
      def restart, do: Tarearbol.InternalWorker.restart(__internal_worker_module__())
    end
  end

  @doc false
  def __on_definition__(%Macro.Env{module: mod}, kind, name, args, _guards, body) do
    generated =
      body
      |> Macro.prewalk(nil, fn
        {_, meta, _} = t, nil -> {t, Keyword.get(meta, :generated)}
        t, acc -> {t, acc}
      end)
      |> elem(1)

    report_override(generated, mod, kind, name, length(args))
  end

  @reserved ~w|
    start_link init state
    get del put restart
    asynch_call synch_call
    multidel multiput
    __init_handler__
    __namespace__
    __dynamic_supervisor_module__ __internal_worker_module__ __registry_module__ __state_module__
  |a
  defp report_override(nil, mod, kind, name, arity) when name in @reserved,
    do:
      Logger.warn("""
      You are trying to override the reserved function in `#{kind} #{inspect(Function.capture(mod, name, arity))}`.
      Please consider choosing another name.
      """)

  defp report_override(_, _, _, _, _), do: :ok
end
