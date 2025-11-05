defmodule EctoBackup.TestPGRepo do
  use Ecto.Repo,
    otp_app: :ecto_backup_project,
    adapter: Ecto.Adapters.Postgres

  def init(_type, opts) do
    username = System.get_env("PGUSER") || "postgres"
    password = System.get_env("PGPASSWORD") || "postgres"
    database = System.get_env("PGDATABASE") || "ecto_backup_test"
    hostname = System.get_env("PGHOST") || "localhost"
    {:ok, [url: "ecto://#{username}:#{password}@#{hostname}/#{database}"] ++ opts}
  end

  def create_db() do
    case Ecto.Adapters.Postgres.storage_up(__MODULE__.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def drop_db() do
    Ecto.Adapters.Postgres.storage_down(__MODULE__.config())
  end

  def create_default_tables() do
    Ecto.Migrator.with_repo(__MODULE__, fn _repo ->
      query = """
        CREATE TABLE "test_table" (
          "id" bigserial,
          "foo" varchar(255),
          "bar" integer,
          "baz" boolean,
          "inserted_at" timestamp(0) NOT NULL,
          "updated_at" timestamp(0) NOT NULL,
          PRIMARY KEY ("id")
        )
      """

      query!(query, [], log: false)
    end)
  end

  def insert_test_data(n \\ 10) do
    Ecto.Migrator.with_repo(__MODULE__, fn _repo ->
      {^n, nil} =
        insert_all(
          "test_table",
          for n <- 1..n do
            %{
              foo: "foo_#{n}",
              bar: n,
              baz: rem(n, 3) == 0,
              inserted_at: NaiveDateTime.utc_now(),
              updated_at: NaiveDateTime.utc_now()
            }
          end,
          log: false
        )
    end)
  end
end
