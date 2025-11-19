defmodule EctoBackup.SecondPGRepo do
  use Ecto.Repo,
    otp_app: :ecto_backup_project,
    adapter: Ecto.Adapters.Postgres

  def init(type, opts) do
    EctoBackup.TestPGRepo.init(type, opts)
  end
end
