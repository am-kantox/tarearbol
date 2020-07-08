defmodule Tarearbol.Job do
  @moduledoc false

  @type job :: (() -> any()) | {atom(), atom(), [any()]}

  require Logger
  alias Tarearbol.Utils

  if Tarearbol.telemetria?(), do: use(Telemetria, action: :import)

  @task_retry Application.get_env(:tarearbol, :retry_log_prefix, "⚐")
  @task_fail Application.get_env(:tarearbol, :fail_log_prefix, "⚑")

  @spec ensure(job :: job(), opts :: keyword()) :: {:error, any()} | {:ok, any()}
  def ensure(job, opts \\ []) when is_function(job, 0) or is_tuple(job) do
    do_retry(job, Utils.opts(opts), attempts(opts))
  end

  @spec ensure!(job :: job(), opts :: keyword()) :: no_return() | {:error, any()} | {:ok, any()}
  def ensure!(job, opts \\ []) when is_function(job, 0) or is_tuple(job) do
    case ensure(job, opts) do
      {:ok, result} ->
        result

      # raise
      {:error, data} ->
        return_or_raise(job, data, true)
    end
  end

  ##############################################################################

  if Tarearbol.telemetria?(), do: @telemetria(level: :info)
  @spec on_callback(any(), any(), binary(), keyword()) :: any()
  defp on_callback(value, data, log_prefix, level: level) do
    case value do
      level when is_atom(level) ->
        do_log(level, "[#{log_prefix}] #{inspect(data)}")

      fun when is_function(fun, 0) ->
        fun.()

      fun when is_function(fun, 1) ->
        fun.(data)

      {mod, fun, args} when is_list(args) ->
        arities =
          mod
          |> apply(:__info__, [:functions])
          |> Keyword.get_values(fun)

        args_length = Enum.count(args)

        params =
          cond do
            Enum.member?(arities, 1 + args_length) -> [data | args]
            Enum.member?(arities, args_length) -> args
            true -> nil
          end

        if params, do: apply(mod, fun, params)

      {mod, fun} ->
        on_callback({mod, fun, []}, data, log_prefix, level: level)

      _ ->
        nil
    end
  end

  @spec on_success(any(), any(), keyword()) :: any()
  defp on_success(value, data, level: level),
    do: on_callback(value, data, inspect(__MODULE__), level: level)

  @spec on_problem(any(), any(), binary(), keyword()) :: any()
  defp on_problem(value, data, log_prefix, level: level),
    do: on_callback(value, data, log_prefix, level: level)

  @spec delay(opts :: keyword()) :: :ok
  defp delay(opts) do
    opts
    |> Keyword.get(:delay, :infinity)
    |> Tarearbol.Utils.interval()
    |> abs()
    |> Process.sleep()
  end

  defp attempts(opts) do
    opts
    |> Keyword.get(:attempts, :infinity)
    |> Tarearbol.Utils.interval()
  end

  defp do_log(nil, _message), do: nil
  defp do_log(level, message), do: Logger.log(level, message)

  #############################################################################

  @spec return_or_raise(job(), any(), boolean()) :: no_return() | {:error, map()}
  defp return_or_raise(job, data, true),
    do: raise(Tarearbol.TaskFailedError, outcome: data, job: job)

  defp return_or_raise(job, data, false), do: {:error, %{outcome: data, job: job}}

  defp retry_or_die(cause, job, opts, data, retries_left) when retries_left == 0 do
    on_problem(opts[:on_fail], %{cause: cause, data: data}, @task_fail, level: :error)
    return_or_raise(job, data, opts[:raise])
  end

  defp retry_or_die(cause, job, opts, data, retries_left) do
    on_problem(opts[:on_retry], %{cause: cause, data: data}, @task_retry, level: :warn)
    do_retry(job, opts, retries_left - 1)
  end

  defp do_retry(job, opts, retries_left) do
    task = Tarearbol.Application.task!(job)
    yielded = Task.yield(task, opts[:timeout]) || Task.shutdown(task)

    case {opts[:accept_not_ok], yielded} do
      {_, {:exit, data}} ->
        delay(opts)
        retry_or_die(:on_raise, job, opts, data, retries_left)

      {_, {:error, data}} ->
        delay(opts)
        retry_or_die(:on_error, job, opts, data, retries_left)

      {_, {:ok, {:error, data}}} ->
        delay(opts)
        retry_or_die(:on_error, job, opts, data, retries_left)

      {_, {:ok, :ok}} ->
        on_success(opts[:on_success], :ok, level: :info)
        {:ok, :ok}

      {_, {:ok, {:ok, data}}} ->
        on_success(opts[:on_success], data, level: :info)
        {:ok, data}

      {true, {:ok, data}} ->
        on_success(opts[:on_success], data, level: :info)
        {:ok, data}

      {false, {:ok, data}} ->
        delay(opts)
        retry_or_die(:not_ok, job, opts, data, retries_left)

      {_, nil} ->
        delay(opts)
        retry_or_die(:timeout, job, opts, nil, retries_left)

      {_, that_can_not_happen_but} ->
        delay(opts)
        retry_or_die(:unknown, job, opts, that_can_not_happen_but, retries_left)
    end
  end
end
