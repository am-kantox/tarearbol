defmodule Tarearbol do
  @moduledoc """
  `Tarearbol` module provides an interface to run tasks in easy way.

  ## Examples

      iex> result = Tarearbol.ensure(fn -> raise "¡?" end, attempts: 1, raise: false)
      iex> {:error, %{job: _job, outcome: outcome}} = result
      iex> {error, _stacktrace} = outcome
      iex> error
      %RuntimeError{message: "¡?"}
  """

  @with_telemetria :telemetria
                   |> Application.get_env(:applications, [])
                   |> Keyword.keys()
                   |> Enum.member?(:tarearbol) and
                     match?({:module, Telemetria}, Code.ensure_compiled(Telemetria))

  @doc false
  @spec telemetria? :: boolean()
  def telemetria?, do: @with_telemetria

  @doc """
  Ensures the task to be completed; restarts it when necessary.

  Possible options:
  - `attempts` [_default:_ `:infinity`] Might be any of `@Tarearbol.Utils.interval`
    type (`5` for five attempts, `:random` for the random amount etc)
  - `delay` [_default:_ `1 msec`]. Might be any of `@Tarearbol.Utils.interval`
    type (`1_000` or `1.0` for one second, `:timeout` for five seconds etc)
  - `on_success` [_default:_ `nil`], the function to be called on successful
    execution (`arity ∈ [0, 1]` or tuple `{Mod, fun}` where `fun` is of arity
    zero or one.) When the arity of given function is `1`, the result of
    task execution is passed
  - `on_retry` [_default:_ `nil`], same as above, called on retries after
    insuccessful attempts **or** one of `[:debug, :info, :warn, :error]` atoms
    to log a retry with default logger
  - `on_fail` [_default:_ `nil`], same as above, called when the task finally
    failed after `attempts` amount of insuccessful attempts
  """
  @spec ensure((() -> any()) | {atom(), atom(), list()}, keyword()) ::
          {:error, any} | {:ok, any}
  def ensure(job, opts \\ []), do: Tarearbol.Job.ensure(job, opts)

  @doc """
  Same as `Tarearbol.ensure/2`, but it raises on fail and returns the result
    itself on successful execution.
  """
  @spec ensure!((() -> any()) | {atom(), atom(), list()}, keyword()) ::
          {:error, any} | {:ok, any}
  def ensure!(job, opts \\ []), do: Tarearbol.Job.ensure!(job, opts)

  @doc "Spawns an ensured job asynchronously, passing all options given."
  @spec spawn_ensured((() -> any()) | {atom(), atom(), list()}, keyword()) :: Task.t()
  def spawn_ensured(job, opts),
    do: Tarearbol.Errand.run_in(job, :none, Keyword.merge(opts, sidekiq: true, on_retry: :warn))

  @doc "Wrapper for [`Task.Supervisor.async_stream/4`](https://hexdocs.pm/elixir/Task.Supervisor.html#async_stream/4)."
  @spec ensure_all_streamed([(() -> any()) | {atom(), atom(), list()}], keyword()) :: %Stream{
          :done => nil,
          :funs => nonempty_maybe_improper_list()
        }
  def ensure_all_streamed(jobs, opts \\ []),
    do: Tarearbol.Jobs.ensure_all_streamed(jobs, opts)

  @doc "Executes `Tarearbol.ensure_all_streamed/2` and collects tasks results."
  @spec ensure_all([(() -> any()) | {atom(), atom(), list()}], keyword()) :: [
          {:error, any} | {:ok, any}
        ]
  def ensure_all(jobs, opts \\ []), do: Tarearbol.Jobs.ensure_all(jobs, opts)

  @doc """
  Runs a task specified by the first argument in a given interval.

  See [`Tarearbol.ensure/2`] for all possible variants of the `interval` argument.
  """
  @spec run_in(
          (() -> any()) | {atom(), atom(), list()},
          atom() | integer() | float(),
          keyword()
        ) :: Task.t()
  def run_in(job, interval, opts \\ []), do: Tarearbol.Errand.run_in(job, interval, opts)

  @doc """
  Runs a task specified by the first argument at a given time.

  If the second parameter is a [`DateTime`] struct, the task will be run once.
  If the second parameter is a [`Time`] struct, the task will be run at that time
    on daily basis.
  """
  @spec run_at(
          (() -> any()) | {atom(), atom(), list()},
          DateTime.t() | String.t(),
          keyword()
        ) :: Task.t()
  def run_at(job, at, opts \\ []), do: Tarearbol.Errand.run_at(job, at, opts)

  @doc "Spawns the task for the immediate async execution."
  @spec spawn((() -> any()) | {atom(), atom(), list()}, keyword()) :: Task.t()
  def spawn(job, opts \\ []), do: Tarearbol.Errand.spawn(job, opts)

  @doc "Executes all the scheduled tasks immediately, cleaning up the queue."
  @spec drain() :: [{:error, any} | {:ok, any}]
  def drain(jobs \\ Tarearbol.Application.jobs())
  def drain([]), do: []

  def drain(jobs) do
    Tarearbol.Application.kill()
    for {job, _at, opts} <- jobs, do: Tarearbol.ensure(job, opts)
  end
end
