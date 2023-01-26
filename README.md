# Tarearbol    [![Kantox ❤ OSS](https://img.shields.io/badge/❤-kantox_oss-informational.svg)](https://kantox.com/)  ![Test](https://github.com/am-kantox/tarearbol/workflows/Test/badge.svg)  ![Dialyzer](https://github.com/am-kantox/tarearbol/workflows/Dialyzer/badge.svg)

**Lightweight task manager, allowing retries, callbacks, assurance that the task succeeded, and more…**

## Installation

```elixir
def deps do
  [
    {:tarearbol, "~> 1.2"}
  ]
end
```

## Features

### Task supervision tree for granted

Add `:tarearbol` to the list of applications and you are all set.

### Infinite retries

```elixir
Tarearbol.ensure fn ->
  unless Enum.random(1..100) == 42, do: raise "Incorrect answer"
  {:ok, 42}
end

# some bad-case logging
{:ok, 42}
```

### Async execution of many tasks with retries

```elixir
res = 1..20
      |> Enum.map(fn i ->
        fn -> Process.sleep(Enum.random(1..i)); i end
      end)
      |> Tarearbol.Job.ensure_all(attempts: 1)

[{:ok, 1}, {:ok, 2}, ..., {:ok, 20}]
```

### Limited amount of retries

```elixir
Tarearbol.ensure fn ->
  raise "Incorrect answer"
end, attempts: 10

# some bad-case logging
{:error,
 %{job: #Function<20.87737649/0 in :erl_eval.expr/5>,
   outcome: {%RuntimeError{message: "Incorrect answer"},
    [{:erl_eval, :do_apply, 6, [file: 'erl_eval.erl', line: 668]},
     {Task.Supervised, :do_apply, 2,
      [file: 'lib/task/supervised.ex', line: 85]},
     {Task.Supervised, :reply, 5, [file: 'lib/task/supervised.ex', line: 36]},
     {:proc_lib, :init_p_do_apply, 3, [file: 'proc_lib.erl', line: 247]}]}}}
```

### Delay between retries

```elixir
Tarearbol.ensure fn ->
  unless Enum.random(1..100) == 42, do: raise "Incorrect answer"
  {:ok, 42}
end, delay: 1000

# some slow bad-case logging
{:ok, 42}
```

### Callbacks

```elixir
Tarearbol.ensure fn ->
  unless Enum.random(1..100) == 42, do: raise "Incorrect answer"
  {:ok, 42}
end, on_success: fn data -> IO.inspect(data, label: "★") end,
     on_retry: fn data -> IO.inspect(data, label: "☆") end

# some slow bad-case logging
# ⇓⇓⇓⇓ one or more of ⇓⇓⇓⇓
☆: %{cause: :on_raise,
  data: {%RuntimeError{message: "Incorrect answer"},
   [{:erl_eval, :do_apply, 6, [file: 'erl_eval.erl', line: 670]},
    {:erl_eval, :exprs, 5, [file: 'erl_eval.erl', line: 122]},
    {Task.Supervised, :do_apply, 2, [file: 'lib/task/supervised.ex', line: 85]},
    {Task.Supervised, :reply, 5, [file: 'lib/task/supervised.ex', line: 36]},
    {:proc_lib, :init_p_do_apply, 3, [file: 'proc_lib.erl', line: 247]}]}}
# ⇑⇑⇑⇑ one or more of ⇑⇑⇑⇑
★: 42
{:ok, 42}
```

### Allowed options

- `attempts` integer, an amount of attempts before giving up, `0` for forever; default: `:infinity`
- `delay` the delay between attempts, default: `:none`;
  - `raise`: when `true`, will raise after all attempts were unsuccessful, or return `{:error, outcome}` tuple otherwise, default: `false`;
- `accept_not_ok`: when `true`, any result save for `{:error, _}` will be accepted as correct, otherwise only `{:ok, _}` is treated as correct, default: `true`;
- `on_success`: callback when the task returned a result, default: `nil`;
- `on_retry`: callback when the task failed and scheduled for retry, default: `:debug`;
- `on_fail`: callback when the task completely failed, default: `:warn`.

for `:attempts` and `:delay` keys one might specify the following values:

- `integer` → amount to be used as is (milliseconds for `delay`, number for attempts);
- `float` → amount of thousands, rounded (seconds for `delay`, thousands for attempts);
- `:none` → `0`;
- `:tiny` → `10`;
- `:medium` → `100`;
- `:infinity` → `-1`, `:attempts` only.

### Task spawning

```elixir
Tarearbol.run_in fn -> IO.puts(42) end, 1_000 # 1 sec
Tarearbol.spawn fn -> IO.puts(42) end # immediately
```

### Task draining

```elixir
Tarearbol.run_in fn -> IO.inspect(42) end, 1_000 # 1 sec
Tarearbol.run_in fn -> IO.inspect(:foo) end, 1_000 # 1 sec
Tarearbol.drain
42       # immediately, from `IO.inspect`
:foo     # immediately, from `IO.inspect`
[ok: 42, ok: :foo] # immediately, the returned value(s)
```

### [Dynamic Workers Management](https://hexdocs.pm/tarearbol/dynamic_workers_management.html)

### Changelog

- **`1.7.0`** less aggressive `Map.update!/3` + modern era update
- **`1.6.0`** `HashRing` default for `synch`/`asynch` calls in `Tarearbol.DynamicWorker` selection (to preserve idempotency amongst calls)
- **`1.5.0`** defaults for `payload`, `timeout` and `lull` accepted in `use DynamicManager` options as `defaults: …`
- **`1.4.4`** `DynamicManager` accepts `{:payload, payload}` message to update a payload
- **`1.4.3`** accept function heads with `defsynch/1` and `defasynch/1`
- **`1.4.1`** random pool worker by default, pass `:stream`, or override `__free_worker__` if needed
- **`1.4.0`**
  - **`Tarearbol.Pool`** to easily create worker pools on top of `Tarearbol.DynamicManager`
  - **`cast/2`, `call/3`, `terminate/2`** callbacks for workers to initiale message passing from outside
  - **`init:`** argument in call to `use Tarearbol.DynamicManager` to allow custom payload initialization (routed to `handle_continue/2` of underlying process)
- **`1.3.0`** standardized types, better docs;
- **`1.2.1`** `cast/2` and standard replies from worker (:halt | :replace | :ok | any()};
- **`1.2.0`** `call/3` and `terminate/2` callbacks in `DynamicManager`, `0` timeout for `perform/2`;
- **`1.1.2`** transparent support for `Ecto` retries;
- **`1.0.0`** deprecated local functions in `run_in`/`run_at` in favor of `Tarearbol.Scheduler`;
- **`0.6.0`** code format, explicit `Task.shutdown`;
- **`0.5.0`** using `DETS` to store `run_at` jobs;
- **`0.4.2`** `Tarearbol.spawn_ensured/2`;
- **`0.4.1`** `run_at` now repeats itself properly;
- **`0.4.0`** allow `run_at` recurrent tasks.

### [Documentation](https://hexdocs.pm/tarearbol)
