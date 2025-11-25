defmodule EctoBackup.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [EctoBackup.State]
    opts = [strategy: :one_for_one, name: EctoBackup.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
