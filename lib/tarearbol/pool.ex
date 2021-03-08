defmodule Tarearbol.Pool do
  @moduledoc """
  The pool of workers.
  """

  alias Tarearbol.Utils

  defmacro __using__(opts) do
    pool_size = Utils.get_opt(opts, :pool_size, 5)
    timeout = Utils.get_opt(opts, :pool_timeout, 0)

    payload =
      opts
      |> Keyword.get(:payload, %{})
      |> Macro.escape()

    continue = Keyword.get(opts, :continue)

    ast =
      quote generated: true, location: :keep do
        use Tarearbol.DynamicManager, continue: unquote(continue)

        # @before_compile Tarearbol.Pool
        # @on_definition Tarearbol.Pool

        import Tarearbol.Pool, only: [defsynch: 2, defasynch: 2]

        def children_specs do
          for i <- 1..unquote(pool_size),
              into: %{},
              do: {i, payload: unquote(payload), timeout: unquote(timeout)}
        end

        defoverridable children_specs: 0
      end

    ast
  end

  @spec params(:call | :cast, {module(), keyword(), [ast]}) :: ast when ast: Macro.t()
  defp params(:call, {fun, meta, params}),
    do: [{:{}, meta, [fun | params]}, {:_from, [], Elixir}, {:κ, [], Elixir}]

  defp params(:cast, {fun, meta, params}),
    do: [{:{}, meta, [fun | params]}, {:κ, [], Elixir}]

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

  defmacro defsynch(definition, opts),
    do: do_def(:call, definition, opts)

  defmacro defasynch(definition, opts),
    do: do_def(:cast, definition, opts)

  @interface %{cast: :asynch_call, call: :synch_call}
  defp do_def(synch, definition, opts) do
    definition
    |> case do
      {:when, meta, [fun, guards]} ->
        [param | _] = params = params(synch, fun)

        [
          {:def, meta, [{:when, meta, [{synch, [context: Elixir], params}, guards]}, opts]},
          {:def, [context: Elixir, import: Kernel],
           [fun, [do: {@interface[synch], [], [nil, param]}]]}
        ]

      {_fun, meta, _params} = fun ->
        [param | _] = params = params(synch, fun)

        [
          {:def, meta, [{synch, [context: Elixir], params}, opts]},
          {:def, [context: Elixir, import: Kernel],
           [fun, [do: {@interface[synch], [], [nil, param]}]]}
        ]
    end
    |> Macro.prewalk(fn
      {:state!, meta, []} -> {:κ, meta, Elixir}
      {:id!, meta, []} -> {:elem, [context: Elixir, import: Kernel], [{:κ, meta, Elixir}, 0]}
      {:payload!, meta, []} -> {:elem, [context: Elixir, import: Kernel], [{:κ, meta, Elixir}, 1]}
      other -> other
    end)
  end

  # def __on_definition__(_env, kind, name, args, guards, body) do
  #   # IO.inspect({kind, name, args, guards, body}, limit: :infinity)
  # end

  # def __before_compile__(env) do
  #   # IO.inspect(env, limit: :infinity)
  # end
end