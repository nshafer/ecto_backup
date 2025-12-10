defmodule EctoBackup.SecondTestRepo do
  use Ecto.Repo,
    otp_app: :ecto_backup,
    adapter: EctoBackup.StubEctoAdapter
end
