defmodule Tarearbol.Job do
  @moduledoc false

  require Logger
  alias Tarearbol.Utils

  @task_retry Application.get_env(:tarearbol, :retry_log_prefix, "⚐")
  @task_fail Application.get_env(:tarearbol, :fail_log_prefix, "⚑")

  def ensure(job, opts \\ []) when is_function(job, 0) or is_tuple(job) do
    do_retry(job, Utils.opts(opts), attempts(opts))
  end

  def ensure!(job, opts \\ []) when is_function(job, 0) or is_tuple(job) do
    case ensure(job, opts) do
      {:ok, result} -> result
      {:error, data} -> return_or_raise(job, data, true) # raise
    end
  end

  ##############################################################################

  defmacrop on_problem(value, data, log_prefix) do
    quote do
      case unquote(value) do
        nil -> :ok
        level when is_atom(level) ->
          do_log(level, "[#{unquote(log_prefix)}] #{inspect unquote(data)}")
        fun when is_function(fun, 0) -> fun.()
        fun when is_function(fun, 1) -> fun.(unquote(data))
        _ -> :ok
      end
    end
  end

  defp delay(opts) do
    opts |> Keyword.get(:delay, :infinity) |> Tarearbol.Utils.interval() |> abs() |> Process.sleep()
  end

  defp attempts(opts) do
    opts |> Keyword.get(:attempts, :infinity) |> Tarearbol.Utils.interval()
  end

  defp do_log(level, message), do: Logger.log level, message

  #############################################################################

  defp return_or_raise(job, data, true),
    do: raise Tarearbol.TaskFailedError, outcome: data, job: job
  defp return_or_raise(job, data, false),
    do: {:error, %{outcome: data, job: job}}

  defp retry_or_die(cause, job, opts, data, retries_left) when retries_left == 0 do
    on_problem(opts[:on_fail], %{cause: cause, data: data}, @task_fail)
    return_or_raise(job, data, opts[:raise])
  end
  defp retry_or_die(cause, job, opts, data, retries_left) do
    on_problem(opts[:on_retry], %{cause: cause, data: data}, @task_retry)
    do_retry(job, opts, retries_left - 1)
  end

  defp do_retry(job, opts, retries_left) do
    case {opts[:accept_not_ok], job |> Tarearbol.Application.task!() |> Task.yield(opts[:timeout])} do
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
        if is_function(opts[:on_success], 1), do: opts[:on_success].(:ok)
        {:ok, :ok}
      {_, {:ok, {:ok, data}}} ->
        if is_function(opts[:on_success], 1), do: opts[:on_success].(data)
        {:ok, data}
      {true, {:ok, data}} ->
        if is_function(opts[:on_success], 1), do: opts[:on_success].(data)
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
