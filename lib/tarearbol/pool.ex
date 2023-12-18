defmodule Tarearbol.Pool do
  @moduledoc since: "1.4.0"
  @moduledoc """
  The pool of workers built on top of `Tarearbol.DynamicManager`.

  ## Configuration options:

  - **`pool_size`** the size of the pool, default: `5`
  - **`payload`** the default payload for all the workers
    (for more complex initialization, use `init` option below)
  - **`init`** custom `init` step as described in  `Tarearbol.DynamicManager` docs

  This module exports `defsynch/2` and `defasynch/2` macros allowing to to declare
    functions that would be managed by a pool behind. Basically, the below would be translated
    into a message passed to the free worker of the pool.

      defsynch synch(n) do
        {:ok, payload!() + n}
      end

  Both macros have three predefined functions declared inside a block

  - **`id!`** returning the `id` of the worker invoked
  - **`payload!`** returning the `payload` of the worker invoked
  - **`state!`** returning the `state` of the worker invoked as a tuple `{id, payload}`
  """

  alias Tarearbol.Utils

  @doc false
  defmacro __using__(opts) do
    pool_size = Utils.get_opt(opts, :pool_size, 5)
    timeout = Utils.get_opt(opts, :pool_timeout, 0)
    pickup = Utils.get_opt(opts, :pickup, :hashring)

    payload =
      opts
      |> Keyword.get(:payload, %{})
      |> Macro.escape()

    init = Keyword.get(opts, :init)

    ast =
      quote location: :keep, generated: true do
        use Tarearbol.DynamicManager,
          init: unquote(init),
          pickup: unquote(pickup),
          defaults: [timeout: unquote(timeout)]

        # @before_compile Tarearbol.Pool
        import Tarearbol.Pool, only: [defsynch: 1, defsynch: 2, defasynch: 1, defasynch: 2]

        def children_specs do
          for i <- 1..unquote(pool_size),
              into: %{},
              do: {i, payload: unquote(payload)}
        end

        defoverridable children_specs: 0
      end

    ast
  end

  @spec fix_fun({atom(), keyword(), nil | [ast]}) :: {atom(), keyword(), [ast]}
        when ast: Macro.t()
  defp fix_fun({name, meta, params}) when is_list(params), do: {name, meta, params}
  defp fix_fun({name, meta, nil}), do: {name, meta, []}

  @spec params(:call | :cast, {atom(), keyword(), [ast]}) :: ast when ast: Macro.t()
  defp params(:call, {fun, meta, params}),
    do: [{:{}, meta, [fun | check_no_defaults(params)]}, {:_from, [], Elixir}, {:κ, [], Elixir}]

  defp params(:cast, {fun, meta, params}),
    do: [{:{}, meta, [fun | check_no_defaults(params)]}, {:κ, [], Elixir}]

  # defp call_reply(opts) do
  #   case Keyword.pop(opts, :do) do
  #     {nil, rest} ->
  #       rest
  #     {{:__block__, meta, exprs}, rest} ->
  #       [last | exprs] = Enum.reverse(exprs)
  #       exprs = [{:reply, {:λ_result, [], Elixir}}, {:=, [], [{:λ_result, [], Elixir}, last]} | exprs]
  #       rest ++ [{:do, {:__block__, meta, Enum.reverse(exprs)}}]
  #     {expr, rest} ->
  #       expr = [{:reply, {:λ_result, [], Elixir}}, {:=, [], [{:λ_result, [], Elixir}, expr]}]
  #       rest ++ [{:do, {:__block__, [], expr}}]
  #   end
  # end

  @doc since: "1.4.0"
  @doc """
  Declares a synchronous function with the same name and block, that will be under the hood
    routed to the free worker to execute. If there is no free worker at the moment,
    returns `:error` otherwise returns `{:ok, result}` tuple.

  This function might return any response recognizable by `t:Tarearbol.DynamicManager.response/0`.
  """
  defmacro defsynch(definition, opts \\ []),
    do: do_def(:call, definition, opts)

  @doc since: "1.4.0"
  @doc """
  Declares an asynchronous function with the same name and block, that will be under the hood
    routed to the free worker to execute. If there is no free worker at the moment,
    returns `:error` otherwise returns `{:ok, result}` tuple.

  This function might return any response recognizable by `t:Tarearbol.DynamicManager.response/0`.
  """
  defmacro defasynch(definition, opts \\ []),
    do: do_def(:cast, definition, opts)

  defp do_def(_synch, fun, []) do
    {:def, [], [fun]}
  end

  @interface %{cast: :asynch_call, call: :synch_call}
  defp do_def(synch, definition, opts) do
    definition
    |> case do
      {:when, meta, [fun, guards]} ->
        fun = fix_fun(fun)
        [param | _] = params = params(synch, fun)

        [
          {:def, meta, [{:when, meta, [{synch, [context: Elixir], params}, guards]}, opts]},
          {:def, [context: Elixir, import: Kernel],
           [fun, [do: {@interface[synch], [], [nil, param]}]]}
        ]

      {_fun, meta, _params} = fun ->
        fun = fix_fun(fun)
        [param | _] = params = params(synch, fun)

        [
          {:def, meta, [{synch, [context: Elixir], params}, opts]},
          {:def, [context: Elixir, import: Kernel],
           [fun, [do: {@interface[synch], [], [nil, param]}]]}
        ]
    end
    |> Macro.prewalk(fn
      {:state!, meta, []} ->
        {:κ, Keyword.put_new(meta, :generated, true), Elixir}

      {:id!, meta, []} ->
        {:elem, [generated: true, context: Elixir, import: Kernel],
         [{:κ, Keyword.put_new(meta, :generated, true), Elixir}, 0]}

      {:payload!, meta, []} ->
        {:elem, [generated: true, context: Elixir, import: Kernel],
         [{:κ, Keyword.put_new(meta, :generated, true), Elixir}, 1]}

      {term, meta, params} ->
        {term, Keyword.put_new(meta, :generated, true), params}

      other ->
        other
    end)
  end

  defp check_no_defaults(params) when is_list(params) do
    Macro.prewalk(params, fn
      {:\\, _, _} ->
        raise ArgumentError, """
        Default values in non-head declaration are not allowed yet. Declare a function head with default values instead.
        """

      other ->
        other
    end)
  end

  # def __before_compile__(env) do
  #   # IO.inspect(env, limit: :infinity)
  # end
end
