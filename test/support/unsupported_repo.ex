defmodule EctoBackup.UnsupportedRepo do
  use Ecto.Repo,
    otp_app: :ecto_backup_project,
    adapter: EctoBackup.UnsupportedAdapter
end
