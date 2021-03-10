# Dynamic Workers Management

## Dynamic Management Examples

There are some ready-to-use snippets [collected here](./dynamic_management_examples.md).

## Architecture

![DynamicManager Architecture](./assets/dynamic_manager.png)

`DynamicSupervisor` is a very handy tool to manage many different task-like processes.
It is used mostly when one does not know in advance how many processes are to be run,
and the processes happen to appear based on some external conditions. A good example
would be a web scraper; we might spawn a process per every new page we need to crawl
and `DynamicSupervisor` would take care about restarting those failed.

It might become slightly cumbersome for the projects requiring more-or-less same
behaviour but when the supervised processes should perform some periodical job,
maybe exit upon job outcome and be accessible by some `id` while they are running.

For the contrived example, imagine the main dashboard that displays the state
of all the computers, connected to the intranet. There are guests with notebooks,
constantly connecting and disconneting. Let’s say we want to maintain a list of
processes spying on our guests (please do not use this library that way, though.)

We need to be able to query the processes for current state / stats by computer ID,
say, MAC-address. The first wild guess would be to convert MACs to alphanumeric
and then to atoms to give names to our workers. And then call them by name.
This approach is not only naïve but also very dangerous. That way we’d DOS our
_ErlangVM_ with atoms. So yeah, the dictionary `MAC → PID` is to be stored
somewhere else. So we already need to have a supervisor, managing the state _and_
`DynamicSupervisor`, which in turn manages workers. Also, upon startup there is
a warming period during which we probably do not want to show anything since the
data might be inaccurate. This warming stage should be probably done from inside
`handle_continue/2` from some another process, and this process cannot be the state
one due to restart strategy `:rest_for_one`, which is required to restart workers
when the state has crashed.

All the problems above are very similar for this kind of task. So, welcome
`DynamicSupervisor` which solves all the problems above automagically, leaving
the consumer with a pure business logic implementation. The only needed thing
to make it all up and running would be to implement `Tarearbol.DynamicManager`
behaviour. It consists of four functions.

###  `children_specs/0`

```elixir
@callback children_specs :: %{required(binary()) => Enum.t()}
```

Return value should be a map of `id → settings` where `id` is the unique
identifier of the process and possible settings values are described in the
documentation.

### `perform/2`

```elixir
@callback perform(id :: binary(), payload :: term()) :: any()
```

The implementation of the worker. This function will be called with
the child `id` as first argument and the `payload` option to child spec
as second argument.

If it returns `:halt`, the process is considered done his job. Any other outcome
will be treated as as a result and stored in the `State`.

### `handle_state_change/1`

```elixir
@callback handle_state_change(state :: :down | :up | :starting | :unknown) :: :ok | :restart
```

This callback will be called on state changes, like `:starting` while the
initial state is not yet fully loaded and `:started` upon readyness.

### `handle_timeout/1`

```elixir
@callback handle_timeout(state :: map()) :: any()
```

This callback will be called if the worker cannot process in a reasonable time.
