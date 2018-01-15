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
      {:ok, result} ->
        result

      # raise
      {:error, data} ->
        return_or_raise(job, data, true)
    end
  end

  ##############################################################################

  defp on_callback(value, data, log_prefix \\ "JOB") do
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
        on_callback({mod, fun, []}, data, log_prefix)

      _ ->
        nil
    end
  end

  defp on_success(value, data), do: on_callback(value, data)
  defp on_problem(value, data, log_prefix), do: on_callback(value, data, log_prefix)

  defp delay(opts) do
    opts |> Keyword.get(:delay, :infinity) |> Tarearbol.Utils.interval() |> abs()
    |> Process.sleep()
  end

  defp attempts(opts) do
    opts |> Keyword.get(:attempts, :infinity) |> Tarearbol.Utils.interval()
  end

  defp do_log(nil, _message), do: nil
  defp do_log(level, message), do: Logger.log(level, message)

  #############################################################################

  defp return_or_raise(job, data, true),
    do: raise(Tarearbol.TaskFailedError, outcome: data, job: job)

  defp return_or_raise(job, data, false), do: {:error, %{outcome: data, job: job}}

  defp retry_or_die(cause, job, opts, data, retries_left) when retries_left == 0 do
    on_problem(opts[:on_fail], %{cause: cause, data: data}, @task_fail)
    return_or_raise(job, data, opts[:raise])
  end

  defp retry_or_die(cause, job, opts, data, retries_left) do
    on_problem(opts[:on_retry], %{cause: cause, data: data}, @task_retry)
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
        on_success(opts[:on_success], :ok)
        {:ok, :ok}

      {_, {:ok, {:ok, data}}} ->
        on_success(opts[:on_success], data)
        {:ok, data}

      {true, {:ok, data}} ->
        on_success(opts[:on_success], data)
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
