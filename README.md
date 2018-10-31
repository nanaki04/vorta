# Vorta

## Summary

Vorta is a library that wraps genservers in order to automatically clones their state,
and recovers it in case of a crash using supervisors.

### Examples

```elixir
    iex> defmodule State.Player do
    ...>   use Vorta
    ...> end
    ...>
    ...> State.Player.new({1, %{name: "Jessie"}})
    {:ok, {1, %{name: "Jessie"}}}
    iex> State.Player.update(1, fn {id, player} -> ResultEx.return({{id, %{player | name: "Sol"}}, "Reply"}) end)
    {:ok, {:some, "Reply"}}
    iex> State.Player.fetch(1)
    {:ok, {1, %{name: "Sol"}}}
    iex> State.Player.sleep(1)
    ...> State.Player.up?(1)
    false
    iex> State.Player.fetch(1)
    {:ok, {1, %{name: "Sol"}}}
    iex> State.Player.up?(1)
    true
```

## Middleware

Middleware can be registered to keep track of state changes, prevent updates when the state is in a certain condition, or return mock data without actually performing updates or other similar functionality.

### Examples

```elixir
    iex> defmodule State.Player.Mock do
    ...>   use Entangle.Thorn, layers: [:test]
    ...> 
    ...>   @spec run(Vorta.middleware) :: Vorta.middleware
    ...>   def run(next) do
    ...>     fn
    ...>       {:new, state, updater} ->
    ...>         next.({:new, state, updater})
    ...>       {:update, state, _updater} ->
    ...>         mock = {4, %{name: "Mock Mockery"}}
    ...>         next.({:update, state, fn state -> {:ok, {state, mock}} end})
    ...>       {:delete, state, updater} ->
    ...>         next.({:delete, state, updater})
    ...>     end
    ...>   end
    ...> end
    ...> 
    ...> defmodule State.Player.Middleware do
    ...>   use Entangle.Seed
    ...> 
    ...>   layers([:test, :dev, :prod])
    ...>   active_layers([Mix.env()])
    ...> 
    ...>   root(State.Player.Mock)
    ...> end
    ...> 
    ...> defmodule State.Player.Example do
    ...>   use Vorta, settings: State.Player.Middleware
    ...> end
    ...> 
    ...> State.Player.Example.new({4, %{name: "Mike"}})
    {:ok, {4, %{name: "Mike"}}}
    iex> State.Player.Example.update(4, fn state -> {:ok, {state, state}}  end)
    {:ok, {:some, {4, %{name: "Mock Mockery"}}}}
    iex> State.Player.Example.fetch(4)
    {:ok, {4, %{name: "Mike"}}}
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `vorta` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:vorta, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/vorta](https://hexdocs.pm/vorta).

