# Dynamic Management Examples

## Schedule Work

```elixir
defmodule Counter do
  alias Tarearbol.DynamicManager
  use DynamicManager

  @impl DynamicManager
  def children_specs do
    now = DateTime.utc_now()
    %{
      second: [payload: now, timeout: 1_000],
      minute: [payload: now, timeout: 60_000]
    }
  end

  @impl DynamicManager
  def perform(:second, payload) do
    now = DateTime.utc_now()
    IO.inspect({payload, now}, label: "sec")
    {:ok, now} # do not replace a payload
  end

  def perform(:minute, payload) do
    now = DateTime.utc_now()
    IO.inspect({payload, now}, label: "min")
    {:replace, now} # replace a payload
  end
end
```

Once started with `Counter.start_link()`, it’ll output:

```
sec: {~U[2021-03-10 07:58:55.874591Z], ~U[2021-03-10 07:58:56.876633Z]}
...
sec: {~U[2021-03-10 07:58:55.874591Z], ~U[2021-03-10 07:59:54.938543Z]}
min: {~U[2021-03-10 07:58:55.874591Z], ~U[2021-03-10 07:59:55.876592Z]}
sec: {~U[2021-03-10 07:58:55.874591Z], ~U[2021-03-10 07:59:55.939661Z]}
...
sec: {~U[2021-03-10 07:58:55.874591Z], ~U[2021-03-10 08:00:54.998537Z]}
min: {~U[2021-03-10 07:59:55.876592Z], ~U[2021-03-10 08:00:55.877658Z]}
...
```

Note, that the payload of the `:second` one does not change, while the payload of `minute` gets updated to the latest value reported.

## Workers Pool

One might create a workers pool with a help of `Tarearbol.DynamicManager`. Usually `perform/2` is suppressed in workers with `timeout: 0` and only `Genserver.cast/2` and `Genserver.call/2` are handled with helpers `Tarearbol.Pool.defsynch/2` and `Tarearbol.Pool.defasynch/2`.

Written as a regular functions, they are wrapped during compilation time to be dispatched to the free instance of the pool behind. Inside the body of these functions, the following magic macros become available:

- **`id!`** returning the `id` of the worker invoked
- **`payload!`** returning the `payload` of the worker invoked
- **`state!`** returning the `state` of the worker invoked as a tuple `{id, payload}`

```elixir
defmodule Pool do
  use Tarearbol.Pool, init: &Pool.initializer/0, pool_size: 2

  def initializer, do: 0

  defsynch synch(),
    do: {:ok, payload!()}

  defsynch synch(n),
    do: {:ok, payload!() + n}

  defasynch asynch(n),
    do: {:replace, payload!() + n}
end
```

Now one might call `Pool.synch/1` to perform a synchronized pooled state request, as well as `Pool.asynch/1` to asynchronously update the state. Note, that in this contrived example, the state of the _first free worker_ is going to be updated.

```elixir
Pool.start_link()

Enum.map(1..3, &Pool.synch(&1))
#⇒ [ok: 1, ok: 2, ok: 3]
Pool.synch()
#⇒ 0 
```

But for `asynch/1` function that needs some time to finish _and_ updates the state, it’s different.

```elixir
Pool.start_link()

Enum.map(1..3, &Pool.asynch(&1))
#⇒ [:ok, :ok, :ok]
Enum.reduce(Pool.state().children, 0, & &2 + elem(&1, 1).value)
#⇒ 6
```

Note, that there is no guarantee what worker would handle each call.

## Multiple Stateful Processes

Consider we are building an online shop having buckets for each customer. Then we might back up the customer session with this kind of `DynamicManager`.

```elixir
defmodule Bucket do
  alias Tarearbol.DynamicManager
  use DynamicManager

  def new(customer) do
    put(customer, payload: %{}, timeout: 10_000)
  end

  def do_smth(customer) do
    IO.inspect("Hey, #{customer}, we have a discount")
  end

  @impl DynamicManager
  def children_specs, do: %{}

  @impl DynamicManager
  def perform(id, payload) do
    if map_size(payload) > 0, do: do_smth(id)
    {:ok, DateTime.utc_now()}
  end

  @impl Tarearbol.DynamicManager
  def call(:<, _from, {_id, payload}),
    do: {:ok, payload}

  @impl Tarearbol.DynamicManager
  def cast({:+, item}, {_id, payload}),
    do: {:replace, Map.update(payload, item, 1, & &1+1)}
end
```

Then we can play with it.

```elixir
iex|1▸ Bucket.start_link()
{:ok, #PID<0.325.0>}
iex|2▸ Bucket.new "Aleksei"  
:ok
iex|3▸ Bucket.synch_call "Aleksei", {:+, :tomato}
iex|4▸ Bucket.asynch_call "Aleksei", {:+, :tomato}
iex|5▸ Bucket.asynch_call "Aleksei", {:+, :cucumber}
# the below is printed from `perform/2`
"Hey, Aleksei, we have a discount"                   
iex|6▸ Bucket.synch_call "Aleksei", :<
{:ok, %{cucumber: 1, tomato: 2}}
```