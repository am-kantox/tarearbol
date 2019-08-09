defmodule Tarearbol.TaskFailedError do
  defexception [:outcome, :message, :job]

  def exception(outcome: outcome, job: job) do
    message = "Task failed after given amount of tries. Status is: [#{inspect(outcome)}]."
    %Tarearbol.TaskFailedError{outcome: outcome, job: job, message: message}
  end
end
