defmodule Vorta.Clone do
  @moduledoc """
  The `Vorta.Clone` is automatically started and used to backup state from `Vorta` servers.
  Since this process is handled automatically from the `Vorta` module, this module is not intended to be used directly.
  """

  @doc false
  @callback name(Vorta.id()) :: GenServer.name()

  @doc false
  @callback stop(Vorta.id()) :: {:ok, Vorta.id()} | {:error, term}

  @doc false
  @callback clone(Vorta.state()) :: {:ok, Vorta.state()} | {:error, term}

  @doc false
  @callback retrieve(Vorta.id()) :: {:ok, Vorta.state()} | {:error, term}

  @doc false
  @callback start_link(Vorta.state()) :: GenServer.on_start()

  @doc false
  @callback up?(Vorta.id()) :: boolean

  defmacro __using__(_opts) do
    quote do
      @behaviour Vorta.Clone

      use GenServer

      @impl Vorta.Clone
      def name(id) do
        {:via, Registry, {Vorta.Registry, to_string(__MODULE__) <> to_string(id)}}
      end

      @impl Vorta.Clone
      def stop(id) do
        GenServer.whereis(name(id))
        |> Option.return()
        |> Option.map(fn pid -> DynamicSupervisor.terminate_child(Vorta.Spawner, pid) end)
        |> Option.map(fn
          :ok -> {:ok, id}
          error -> error
        end)
        |> Option.or_else({:ok, id})
      end

      @impl Vorta.Clone
      def clone({id, state}) do
        ensure_alive(id)
        |> Result.bind(fn id -> GenServer.call(name(id), {:clone, {id, state}}) end)
      end

      @impl Vorta.Clone
      def retrieve(id) do
        if up?(id), do: GenServer.call(name(id), :retrieve), else: {:error, :no_clone}
      end

      @impl Vorta.Clone
      def up?(id) do
        GenServer.whereis(name(id))
        |> Option.return()
        |> Option.to_bool()
      end

      @spec ensure_alive(Vorta.id()) :: {:ok, Vorta.id()} | {:error, term}
      defp ensure_alive(id) do
        if up?(id) do
          {:ok, id}
        else
          case DynamicSupervisor.start_child(Vorta.Spawner, {__MODULE__, {id, {id, nil}}}) do
            {:ok, _} -> {:ok, id}
            :ignore -> {:error, :ignore}
            error -> error
          end
        end
      end

      @impl Vorta.Clone
      def start_link({id, state}) do
        GenServer.start_link(__MODULE__, state, name: name(id))
      end

      @impl GenServer
      def init(state) do
        {:ok, state}
      end

      @impl GenServer
      def handle_call({:clone, state}, _, _), do: {:reply, {:ok, state}, state}

      def handle_call(:retrieve, _, state), do: {:reply, {:ok, state}, state}
    end
  end
end
