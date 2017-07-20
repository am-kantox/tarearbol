defmodule Tarearbol.TaskFailedError do
  defexception [:status, :message, :job]

  def exception(status: status, job: job) do
    message = "Task failed after given amount of tries. Status is: [#{inspect(status)}]."
    %Tarearbol.TaskFailedError{status: status, job: job, message: message}
  end
end
