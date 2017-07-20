defmodule Tarearbol.Job do
  @moduledoc false

  require Logger

  @default_ensure_opts [delay: 0, on_success: nil, on_retry: :debug, on_fail: :debug, raise: false]
  @ensure_opts Application.get_env(:tarearbol, :ensure_opts, @default_ensure_opts)

  @task_retry Application.get_env(:tarearbol, :retry_log_prefix, "⚐")
  @task_fail Application.get_env(:tarearbol, :fail_log_prefix, "⚑")

  def ensure(job, opts \\ []) do
    do_retry(job, Keyword.merge(@ensure_opts, opts), -1)
  end
  def ensure!(job, opts \\ []) do
    with {:ok, result} <- do_retry(job, Keyword.merge(@ensure_opts, opts), -1),
      do: result
  end

  def attempts(job, retries, opts \\ []) do
    do_retry(job, Keyword.merge(@ensure_opts, opts), retries - 1)
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

  defp do_log(level, message), do: Logger.log level, message

  defp return_or_raise(job, data, true),
    do: raise Tarearbol.TaskFailedError, status: data, job: job
  defp return_or_raise(job, data, false),
    do: {:error, %{status: data, job: job}}

  defp retry_or_die(job, opts, data, retries_left) when retries_left == 0 do
    on_problem(opts[:on_fail], data, @task_fail)
    return_or_raise(job, data, opts[:raise])
  end
  defp retry_or_die(job, opts, data, retries_left) do
    on_problem(opts[:on_retry], data, @task_retry)
    do_retry(job, opts, retries_left - 1)
  end

  defp do_retry(job, opts, retries_left) do
    case job |> Tarearbol.Application.task!() |> Task.yield() do
      {:exit, data} ->
        if is_integer(opts[:delay]), do: Process.sleep(opts[:delay])
        retry_or_die(job, opts, data, retries_left)
      result ->
        if is_function(opts[:on_success], 1), do: opts[:on_success].(result)
        result
    end
  end
  # TODO: curry function passed, then start a task
  # def run(fun, args \\ []) when is_function(mod, length(args)),
  #   do: Tasl.Supervisor.start_child(Tarearbol.Application, mod, fun, args)

end
