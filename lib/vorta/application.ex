defmodule Vorta.Application do
  @moduledoc false

  use Application

  @doc false
  def start(_, _) do
    children = [
      {Registry, keys: :unique, name: Vorta.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Vorta.Founder},
      {DynamicSupervisor, strategy: :one_for_one, name: Vorta.Spawner}
    ]

    opts = [strategy: :one_for_one, name: Vorta.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
