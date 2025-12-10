defmodule EctoBackup.SecondTestPGRepo do
  use Ecto.Repo,
    otp_app: :ecto_backup_project,
    adapter: Ecto.Adapters.Postgres

  defdelegate init(type, opts), to: EctoBackup.TestPGRepo
end
