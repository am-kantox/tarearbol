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
end
