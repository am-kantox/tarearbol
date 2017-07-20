defmodule Tarearbol.Simple do
  @moduledoc false

  def run({mod, fun, args}) when is_atom(mod) and is_atom(fun) and is_list(args),
    do: Task.Supervisor.start_child(Tarearbol.Application, mod, fun, args)

  def run(fun) when is_function(fun, 0),
    do: Task.Supervisor.start_child(Tarearbol.Application, fun)

  # TODO: curry function passed, then start a task
  # def run(fun, args \\ []) when is_function(mod, length(args)),
  #   do: Tasl.Supervisor.start_child(Tarearbol.Application, mod, fun, args)

end
