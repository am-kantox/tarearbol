defmodule Tarearbol.TaskFailedError do
  @moduledoc """
  The generic exception thrown from any function
  dealing with `Task` handling.
  """
  defexception [:outcome, :message, :job]

  @impl true
  def exception(outcome: outcome, job: job) do
    message = "Task failed after given amount of tries. Status is: [#{inspect(outcome)}]."
    %Tarearbol.TaskFailedError{outcome: outcome, job: job, message: message}
  end
end
