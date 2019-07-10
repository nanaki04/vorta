defmodule Vorta do
  alias OptionEx, as: Option
  alias ResultEx, as: Result

  @moduledoc """
  Vorta is a library that wraps genservers in order to automatically clones their state,
  and recovers it in case of a crash using supervisors.

  ### Examples

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

  ## Middleware

  Middleware can be registered to keep track of state changes, prevent updates when the state is in a certain condition, or return mock data without actually performing updates or other similar functionality.

  ### Examples

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

  """

  @typedoc """
  The reply value to be returned when using the update function.
  """
  @type reply :: term

  @typedoc """
  The id value to identify and access dynamic servers.
  """
  @type id :: String.t() | atom | number

  @typedoc """
  The state to be maintained by a server.
  The structure of the state can be of any type, but must be wrapped in a tuple with the id as its first element.
  """
  @type state :: {id, term}

  @typedoc """
  Used in middleware to determine what sort of mutation to the state is taking place.
  """
  @type mutation_type ::
          :new
          | :update
          | :delete

  @typedoc """
  Update function to apply mutations to the state.
  Can be caught and replaced in middleware to return mock data, or cancel updates.
  """
  @type updater :: (state -> {:ok, state} | {:ok, {state, reply}} | {:error, term})

  @typedoc """
  The input passed into middleware as state.
  """
  @type middleware_input :: {mutation_type, state, updater}

  @typedoc """
  The output expected from middleware functions.
  """
  @type middleware_output :: {:ok, state} | {:ok, {state, reply}} | {:error, term}

  @typedoc """
  Type describing the structure of a middleware function.
  """
  @type middleware :: (middleware_input -> middleware_output)

  @doc """
  Create a new server by passing its initial state.
  Note that the state can be of any type, but must be wrapped in a tuple with its id as first element.
  """
  @callback new(state) :: {:ok, state} | {:error, term}

  @doc """
  Update the server state by passing the server id, and an updater function.
  The updater function expects the server current state as input, and expects a tuple with the updated state 
  """
  @callback update(id, (state -> {:ok, state} | {:ok, {state, reply}} | {:error, term})) ::
              {:ok, reply} | {:error, term}

  @doc """
  Fetches the state from the server.
  """
  @callback fetch(id) :: {:ok, state} | {:error, term}

  @doc false
  @callback name(id) :: GenServer.name()

  @doc """
  Temporarily shuts down the server.
  The server state will live on as its `Vorta.Clone`.
  """
  @callback sleep(id) :: {:ok, id} | {:error, term}

  @doc """
  Permanently shut down the server and its clone, losing all associated data.
  """
  @callback delete(id) :: {:ok, id} | {:error, term}

  @doc """
  Start the server.
  This will automatically be called when creating a new server using `Vorta.new/1`.
  """
  @callback start_link(state) :: GenServer.on_start()

  @doc """
  Check if the server is currently up and running.
  """
  @callback up?(id) :: boolean

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Vorta

      seed =
        Keyword.get(opts, :settings)
        |> Option.return()
        |> Option.map(fn
          %Entangle.Seed{} = settings -> settings
          settings -> settings.settings()
        end)
        |> Option.or_else(Entangle.Seed.default_settings())

      use Entangle.Entangler, seed: seed

      @doc false
      entangle(:entangled_new, [
        branch(&__MODULE__.call_new/1)
      ])

      @doc false
      entangle(:entangled_update, [
        branch(&__MODULE__.call_update/1)
      ])

      @doc false
      entangle(:entangled_delete, [
        branch(&__MODULE__.call_delete/1)
      ])

      @before_compile Vorta
    end
  end

  defmacro __before_compile__(env) do
    quote do
      use GenServer

      defmodule unquote(Module.concat(env.module, Clone)) do
        use Vorta.Clone
      end

      @impl Vorta
      def name(id) do
        {:via, Registry, {Vorta.Registry, unquote(to_string(env.module)) <> to_string(id)}}
      end

      @impl Vorta
      def new({id, state}) do
        case DynamicSupervisor.start_child(Vorta.Founder, {unquote(env.module), {id, state}}) do
          {:ok, _} -> {:ok, {id, state}}
          :ignore -> {:error, :ignore}
          error -> error
        end
      end

      @impl Vorta
      def update(id, updater) do
        GenServer.call(name(id), {:update, updater})
      end

      @impl Vorta
      def delete(id) do
        state =
          fetch(id)
          |> Result.or_else(nil)

        entangled_delete({:delete, state, fn _ -> {:ok, nil} end})
        |> Result.bind(fn _ -> shutdown(id) end)
        |> Result.bind(&unquote(Module.concat(env.module, Clone)).stop/1)
      end

      @impl Vorta
      def fetch(id) do
        ensure_awake(id)
        |> Result.bind(fn id -> GenServer.call(name(id), :fetch) end)
      end

      @impl Vorta
      def sleep(id) do
        state =
          fetch(id)
          |> Result.or_else({id, nil})

        unquote(Module.concat(env.module, Clone)).clone(state)
        |> Result.bind(fn _ -> shutdown(id) end)
        |> Result.map(fn _ -> state end)
      end

      @impl Vorta
      def up?(id) do
        GenServer.whereis(name(id))
        |> Option.return()
        |> Option.to_bool()
      end

      @impl Vorta
      def start_link({id, state}) do
        GenServer.start_link(unquote(env.module), {id, state}, name: name(id))
      end

      @impl GenServer
      def terminate(_reason, state) do
        unquote(Module.concat(env.module, Clone)).clone(state)
      end

      @spec ensure_awake(Vorta.id()) :: {:ok, Vorta.id()} | {:error, term}
      defp ensure_awake(id) do
        if up?(id) do
          {:ok, id}
        else
          unquote(Module.concat(env.module, Clone)).retrieve(id)
          |> Result.bind(fn state -> new(state) end)
          |> Result.map(fn _ -> id end)
        end
      end

      @spec shutdown(Vorta.id()) :: {:ok, Vorta.id()} | {:error, term}
      defp shutdown(id) do
        GenServer.whereis(name(id))
        |> Option.return()
        |> Option.map(fn pid -> DynamicSupervisor.terminate_child(Vorta.Founder, pid) end)
        |> Option.map(fn
          :ok -> {:ok, id}
          error -> error
        end)
        |> Option.or_else({:ok, id})
      end

      @impl GenServer
      def init(state) do
        entangled_new({:new, nil, fn _ -> {:ok, state} end})
        |> Result.map(fn
          {{_, _} = state, _} -> state
          state -> state
        end)
      end

      @doc false
      @spec call_new({Vorta.state(), (nil -> {:ok, Vorta.state()})}) :: {:ok, Vorta.state()}
      def call_new({:new, state, updater}) do
        updater.(state)
      end

      @doc false
      @spec call_update(
              {Vorta.state(),
               (Vorta.state() ->
                  {:ok, Vorta.state()} | {:ok, {Vorta.state(), term}} | {:error, term})}
            ) :: {:ok, {Vorta.state(), term}} | {:error, term}
      def call_update({:update, state, updater}) do
        case updater.(state) do
          {:ok, {{_, _} = state, reply}} -> {:ok, {state, reply}}
          {:ok, {_, _} = state} -> {:ok, state}
          {:error, reason} -> {:error, reason}
          _ -> {:error, :unexpected_return_value}
        end
      end

      @doc false
      @spec call_delete({Vorta.state(), (Vorta.state() -> {:ok, nil})}) :: {:ok, nil}
      def call_delete({:delete, state, updater}) do
        updater.(state)
      end

      @impl GenServer
      def handle_call({:update, updater}, _, state) do
        entangled_update({:update, state, updater})
        |> Result.map(fn
          {{id, _} = state, reply} -> {:reply, {:ok, {:some, reply}}, state}
          {id, _} = state -> {:reply, {:ok, :none}, state}
        end)
        |> Result.or_else_with(fn error -> {:reply, {:error, error}, state} end)
      end

      def handle_call(:fetch, _, state), do: {:reply, {:ok, state}, state}
    end
  end
end
