defmodule Tarearbol.Jobs do
  @moduledoc false

  alias Tarearbol.Utils

  @spec ensure_all_streamed([(() -> any()) | {module(), atom(), list()}], Keyword.t()) :: [
          %Stream{}
        ]
  def ensure_all_streamed(list, opts \\ []) do
    {stream_opts, task_opts} = Utils.extract_opts(opts, ~w|max_concurrency ordered on_timeout|a)
    stream_opts = Keyword.merge(stream_opts, timeout: task_opts[:timeout])

    Tarearbol.Application
    |> Task.Supervisor.async_stream(list, Tarearbol.Job, :ensure, [task_opts], stream_opts)
    |> Stream.map(fn
      # Task succeeded
      {:ok, {:ok, whatever}} ->
        {:ok, whatever}

      # Task failed
      {:ok, {:error, whatever}} ->
        {:error, whatever}

      # Task failed on OTP level
      whatever ->
        whatever
    end)
  end

  @spec ensure_all([(() -> any()) | {module(), atom(), list()}], Keyword.t()) :: [
          {:ok, any} | {:error, any}
        ]
  def ensure_all(list, opts \\ []), do: list |> ensure_all_streamed(opts) |> Enum.to_list()
end
