defmodule VortaTest do
  use ExUnit.Case
  doctest Vorta

  test "Setup a vorta server" do
    defmodule Test.State.Player.Logger do
      use Entangle.Thorn

      def run(next) do
        fn {type, state, updater} ->
          IO.inspect(state, label: IO.ANSI.blue() <> "current state" <> IO.ANSI.reset())
          result = next.({type, state, updater})

          ResultEx.map(result, fn
            {{_, _} = state, reply} ->
              IO.inspect(state, label: IO.ANSI.cyan() <> "new state" <> IO.ANSI.reset())
              IO.inspect(reply, label: IO.ANSI.green() <> "reply" <> IO.ANSI.reset())

            state ->
              IO.inspect(state, label: IO.ANSI.cyan() <> "new state" <> IO.ANSI.reset())
          end)

          ResultEx.or_else_with(result, fn error ->
            IO.inspect(error, label: IO.ANSI.red() <> "error updating state" <> IO.ANSI.reset())
          end)

          result
        end
      end
    end

    defmodule Test.State.Player.Middleware do
      use Entangle.Seed

      root(Test.State.Player.Logger)
    end

    defmodule Test.State.Player do
      use Vorta, settings: Test.State.Player.Middleware
    end

    Test.State.Player.new({"Sheep", %{name: "Sheep"}})
    |> Kernel.==({:ok, {"Sheep", %{name: "Sheep"}}})
    |> assert()

    Test.State.Player.update("Sheep", fn {id, player} -> {:ok, {id, %{player | name: "Meep"}}} end)
    |> Kernel.==({:ok, :none})
    |> assert()

    Test.State.Player.update("Sheep", fn _ -> {:error, "Oops"} end)
    |> Kernel.==({:error, "Oops"})
    |> assert()

    Test.State.Player.fetch("Sheep")
    |> Kernel.==({:ok, {"Sheep", %{name: "Meep"}}})
    |> assert()
  end
end
