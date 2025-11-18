defmodule EctoBackup.PGBackupTest do
  use ExUnit.Case
  alias EctoBackup.Error
  alias EctoBackup.ConfError
  alias EctoBackup.TestPGRepo
  alias EctoBackup.UnsupportedRepo
  alias EctoBackup.Adapters.Postgres

  doctest EctoBackup

  setup_all do
    # Create test database for all tests in this module
    TestPGRepo.create_db()
    start_supervised!(TestPGRepo)
    TestPGRepo.create_default_tables()
    TestPGRepo.insert_test_data(10)
    on_exit(fn -> TestPGRepo.drop_db() end)

    Temp.track!()
    backup_dir = Temp.mkdir!(prefix: "ecto_backup_test_")
    # backup_dir = "local/backups"

    {:ok, backup_dir: backup_dir}
  end

  describe "TestPGRepo - EctoBackup.backup/0" do
    test "can backup the default databases", %{backup_dir: backup_dir} do
      Application.put_env(:ecto_backup, :ecto_repos, [TestPGRepo])
      Application.put_env(:ecto_backup, :backup_dir, backup_dir)
      assert {:ok, [{:ok, TestPGRepo, backup_file}]} = EctoBackup.backup()
      assert Postgres.valid_backup_file?(backup_file, ["test_table_one", "test_table_two"])
      File.rm_rf(backup_file)
      Application.delete_env(:ecto_backup, :ecto_repos)
      Application.delete_env(:ecto_backup, :backup_dir)
    end
  end

  describe "TestPGRepo - EctoBackup.backup/1" do
    test "can backup the default databases", %{backup_dir: backup_dir} do
      opts = [repos: [TestPGRepo], backup_dir: backup_dir]
      assert {:ok, [{:ok, TestPGRepo, backup_file}]} = EctoBackup.backup(opts)
      assert Postgres.valid_backup_file?(backup_file, ["test_table_one", "test_table_two"])
    end

    test "can backup to custom file", %{backup_dir: backup_dir} do
      opts = [repos: [TestPGRepo], backup_file: "#{backup_dir}/custom_backup.db"]
      assert {:ok, [{:ok, TestPGRepo, backup_file}]} = EctoBackup.backup(opts)
      assert backup_file == "#{backup_dir}/custom_backup.db"
      assert Postgres.valid_backup_file?(backup_file, ["test_table_one", "test_table_two"])
    end

    test "can backup with overridden adapter in repo_config", %{backup_dir: backup_dir} do
      opts = [
        repos: [{TestPGRepo, [adapter: EctoBackup.Adapters.Postgres]}],
        backup_dir: backup_dir
      ]

      assert {:ok, [{:ok, TestPGRepo, backup_file}]} = EctoBackup.backup(opts)
      assert Postgres.valid_backup_file?(backup_file, ["test_table_one", "test_table_two"])
    end

    test "telemetry events are emitted during backup", %{backup_dir: backup_dir} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:ecto_backup, :backup, :start],
          [:ecto_backup, :backup, :stop],
          [:ecto_backup, :backup, :repo, :start],
          [:ecto_backup, :backup, :repo, :stop],
          [:ecto_backup, :backup, :repo, :progress],
          [:ecto_backup, :backup, :repo, :message]
        ])

      opts = [repos: [TestPGRepo], backup_dir: backup_dir]
      assert {:ok, [{:ok, TestPGRepo, backup_file}]} = EctoBackup.backup(opts)
      assert Postgres.valid_backup_file?(backup_file, ["test_table_one", "test_table_two"])

      assert_received {[:ecto_backup, :backup, :start], ^ref, _measurements, _metadata}
      assert_received {[:ecto_backup, :backup, :stop], ^ref, _measurements, _metadata}
      assert_received {[:ecto_backup, :backup, :repo, :start], ^ref, _measurements, %{repo: _}}
      assert_received {[:ecto_backup, :backup, :repo, :stop], ^ref, _measurements, %{repo: _}}

      assert_received {[:ecto_backup, :backup, :repo, :progress], ^ref,
                       %{completed: _, total: _, percent: _}, %{repo: _}}

      assert_received {[:ecto_backup, :backup, :repo, :message], ^ref, _measurements,
                       %{repo: _, level: _, message: _}}
    end

    test "returns error if given invalid database name", %{backup_dir: backup_dir} do
      opts = [
        repos: [{TestPGRepo, [database: "non_existent_db"]}],
        backup_dir: backup_dir
      ]

      assert {:ok, [{:error, TestPGRepo, _reason}]} = EctoBackup.backup(opts)
    end

    test "returns error if given invalid pg_dump cmd", %{backup_dir: backup_dir} do
      opts = [
        repos: [{TestPGRepo, [pg_dump_cmd: "non_existent_pg_dump"]}],
        backup_dir: backup_dir
      ]

      results = EctoBackup.backup(opts)
      assert {:ok, [{:error, TestPGRepo, %Error{reason: :pg_dump_cmd_not_found}}]} = results
    end

    test "returns error if no repos are specified" do
      opts = [backup_dir: "/tmp"]

      assert {:error, %ConfError{reason: :no_default_repos_in_mix}} = EctoBackup.backup(opts)
    end

    test "returns error if no backup_dir or backup_file is configured" do
      assert {:error, %ConfError{reason: :no_backup_dir_set}} =
               EctoBackup.backup(repos: [TestPGRepo])
    end
  end

  describe "UnsupportedRepo - EctoBackup.backup/1" do
    test "returns error for unsupported adapter" do
      opts = [repos: [UnsupportedRepo], backup_dir: "/tmp"]
      results = EctoBackup.backup(opts)
      assert {:ok, [{:error, _, %Error{reason: :unsupported_ecto_adapter}}]} = results
    end
  end
end
