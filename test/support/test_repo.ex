defmodule EctoBackup.TestRepo do
  use Ecto.Repo,
    otp_app: :ecto_backup,
    adapter: EctoBackup.StubEctoAdapter

  def init(_type, opts) do
    database = System.get_env("REPO_DB") || "ecto_backup_test"
    username = System.get_env("REPO_USER") || "database_user"
    password = System.get_env("REPO_PASS") || "database_password"
    hostname = System.get_env("REPO_HOST") || "localhost"

    {:ok, [url: "ecto://#{username}:#{password}@#{hostname}/#{database}"] ++ opts}
  end
end
