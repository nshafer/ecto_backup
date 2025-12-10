defmodule EctoBackup.Adapters.PostgresTest do
  use ExUnit.Case
  alias EctoBackup.Adapters.Postgres
  alias EctoBackup.TestPGRepo
  alias EctoBackup.SecondTestPGRepo

  @moduletag :postgres

  doctest EctoBackup

  # Note: We purposefully call `EctoBackup.backup/1` and `EctoBackup.restore/2` in these tests to
  #       fully exercise the Postgres adapter in an integration-style test.

  setup_all do
    # Create test database for all tests in this module
    TestPGRepo.create_db()
    start_supervised!(TestPGRepo)
    TestPGRepo.create_default_tables()
    TestPGRepo.insert_test_data(10)
    on_exit(fn -> TestPGRepo.drop_db() end)

    # Create a temporary directory for backups
    Temp.track!()
    backup_dir = Temp.mkdir!(prefix: "ecto_backup_test_")
    # backup_dir = "local/backups"

    {:ok, backup_dir: backup_dir}
  end

  describe "EctoBackup.backup/1 with Postgres adapter" do
    test "can backup a postgres repo", %{backup_dir: backup_dir} do
      opts = [repos: [TestPGRepo], backup_dir: backup_dir]
      assert {:ok, [{:ok, TestPGRepo, backup_file}]} = EctoBackup.backup(opts)
      assert Postgres.valid_backup_file?(backup_file, ["test_table_one", "test_table_two"])
    end

    test "can backup multiple postgres repos", %{backup_dir: backup_dir} do
      opts = [repos: [TestPGRepo, SecondTestPGRepo], backup_dir: backup_dir]
      assert {:ok, results} = EctoBackup.backup(opts)
      assert Enum.count(results) == 2

      for {:ok, repo, backup_file} <- results do
        assert repo in [TestPGRepo, SecondTestPGRepo]
        assert Postgres.valid_backup_file?(backup_file, ["test_table_one", "test_table_two"])
      end
    end

    test "returns error for invalid backup_dir" do
      opts = [repos: [TestPGRepo], backup_dir: "/invalid/backup/dir"]
      assert {:ok, [{:error, TestPGRepo, e}]} = EctoBackup.backup(opts)
      assert e.reason == :pg_dump_failed
    end

    test "returns error for invalid pg_dump cmd", %{backup_dir: backup_dir} do
      opts = [repos: [TestPGRepo], backup_dir: backup_dir, pg_dump_cmd: "invalid_pg_dump_cmd"]
      assert {:ok, [{:error, TestPGRepo, e}]} = EctoBackup.backup(opts)
      assert e.reason == :pg_dump_cmd_not_found
    end

    test "returns error for invalid password", %{backup_dir: backup_dir} do
      opts = [repos: [{TestPGRepo, [password: nil]}], backup_dir: backup_dir]
      assert {:ok, [{:error, TestPGRepo, e}]} = EctoBackup.backup(opts)
      assert e.reason == :pg_dump_failed

      opts = [repos: [{TestPGRepo, [password: ""]}], backup_dir: backup_dir]
      assert {:ok, [{:error, TestPGRepo, e}]} = EctoBackup.backup(opts)
      assert e.reason == :pg_dump_failed

      opts = [repos: [{TestPGRepo, [password: "invalid"]}], backup_dir: backup_dir]
      assert {:ok, [{:error, TestPGRepo, e}]} = EctoBackup.backup(opts)
      assert e.reason == :pg_dump_failed
    end
  end

  def create_backup_file(%{backup_dir: backup_dir}) do
    opts = [repos: [TestPGRepo], backup_dir: backup_dir]
    {:ok, [{:ok, _repo, backup_file}]} = EctoBackup.backup(opts)
    {:ok, backup_file: backup_file}
  end

  describe "EctoBackup.restore/1 with Postgres adapter" do
    setup :create_backup_file

    test "can restore a postgres repo", %{backup_file: backup_file} do
      restore_opts = [repo: TestPGRepo, confirm: true]
      assert {:ok, TestPGRepo} = EctoBackup.restore(backup_file, restore_opts)
    end

    test "returns error for invalid restore file" do
      restore_file = Temp.path!()
      File.write!(restore_file, "invalid content")
      restore_opts = [repo: TestPGRepo, confirm: true]
      assert {:error, TestPGRepo, e} = EctoBackup.restore(restore_file, restore_opts)
      assert e.reason == :pg_restore_list_failed
    end

    test "returns error for invalid pg_restore cmd", %{backup_file: backup_file} do
      restore_opts = [repo: TestPGRepo, confirm: true, pg_restore_cmd: "invalid_pg_restore_cmd"]
      assert {:error, TestPGRepo, e} = EctoBackup.restore(backup_file, restore_opts)
      assert e.reason == :pg_restore_cmd_not_found
    end

    test "returns error when pg_restore fails", %{backup_file: backup_file} do
      # Use an invalid pg_restore argument to force it to fail
      restore_opts = [repo: TestPGRepo, confirm: true, pg_restore_args: ["--blowup"]]
      assert {:error, TestPGRepo, e} = EctoBackup.restore(backup_file, restore_opts)
      assert e.reason == :pg_restore_failed
    end

    test "returns error for invalid password", %{backup_file: backup_file} do
      restore_opts = [repo: {TestPGRepo, [password: nil]}, confirm: true]
      assert {:error, TestPGRepo, e} = EctoBackup.restore(backup_file, restore_opts)
      assert e.reason == :pg_restore_failed

      restore_opts = [repo: {TestPGRepo, [password: ""]}, confirm: true]
      assert {:error, TestPGRepo, e} = EctoBackup.restore(backup_file, restore_opts)
      assert e.reason == :pg_restore_failed

      restore_opts = [repo: {TestPGRepo, [password: "invalid"]}, confirm: true]
      assert {:error, TestPGRepo, e} = EctoBackup.restore(backup_file, restore_opts)
      assert e.reason == :pg_restore_failed
    end

    test "returns error for invalid password value", %{backup_file: backup_file} do
      restore_opts = [repo: {TestPGRepo, [password: :invalid]}, confirm: true]
      assert {:error, TestPGRepo, e} = EctoBackup.restore(backup_file, restore_opts)
      assert e.reason == :invalid_password_value
    end
  end

  describe "valid_backup_file?/3" do
    setup :create_backup_file

    test "returns true for valid backup file", %{backup_file: backup_file} do
      assert Postgres.valid_backup_file?(backup_file, ["test_table_one", "test_table_two"])
    end
  end

  describe "list_backup_file_tables/2" do
    setup :create_backup_file

    test "lists tables in backup file", %{backup_file: backup_file} do
      {:ok, tables} = Postgres.list_backup_file_tables(backup_file)
      assert Enum.sort(tables) == ["test_table_one", "test_table_two"]
    end
  end
end
