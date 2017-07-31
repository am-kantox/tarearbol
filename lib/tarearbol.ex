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

  @doc """
  Hello world.
  """

  def ensure(job, opts \\ []), do: Tarearbol.Job.ensure(job, opts)
  def ensure!(job, opts \\ []), do: Tarearbol.Job.ensure!(job, opts)

  def run_in(job, interval, opts \\ []), do: Tarearbol.Errand.run_in(job, interval, opts)
  def run_at(job, at, opts \\ []), do: Tarearbol.Errand.run_at(job, at, opts)
  def spawn(job, opts \\ []), do: Tarearbol.Errand.spawn(job, opts)

  def drain() do
    jobs = Tarearbol.Application.jobs
    Tarearbol.Application.kill()

    for {job, _opts, _at} <- jobs, do: Tarearbol.ensure(job)
  end
end
