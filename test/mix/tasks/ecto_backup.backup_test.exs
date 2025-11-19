defmodule Mix.Tasks.EctoBackup.BackupTest do
  use ExUnit.Case
  alias EctoBackup.TestPGRepo
  alias EctoBackup.SecondPGRepo

  def raise_err(_repo, _repo_config) do
    raise "Intentional exception for testing"
  end

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

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.Shell.Process.flush() end)
  end

  describe "run/1" do
    test "successfully backs up a specified repo", %{backup_dir: backup_dir} do
      args = ["-r", "EctoBackup.TestPGRepo", "--backup-dir", backup_dir]
      Mix.Tasks.EctoBackup.Backup.run(args)
      assert_received {:mix_shell, :info, ["Backup Summary:"]}
      assert_received {:mix_shell, :info, ["✔ EctoBackup.TestPGRepo" <> _rest]}
      # Mix.Shell.Process.flush(&IO.inspect/1)
    end

    test "successfully backups up a couple default repos", %{backup_dir: backup_dir} do
      Application.put_env(:ecto_backup, :ecto_repos, [TestPGRepo, SecondPGRepo])
      on_exit(fn -> Application.delete_env(:ecto_backup, :ecto_repos) end)

      Application.put_env(:ecto_backup, :backup_dir, backup_dir)
      on_exit(fn -> Application.delete_env(:ecto_backup, :backup_dir) end)

      Mix.Tasks.EctoBackup.Backup.run([])
      assert_received {:mix_shell, :info, ["Backup Summary:"]}
      assert_received {:mix_shell, :info, ["✔ EctoBackup.TestPGRepo" <> rest]}
      assert String.contains?(rest, "✔ EctoBackup.SecondPGRepo")
      # Mix.Shell.Process.flush(&IO.inspect/1)
    end

    test "outputs verbose logs when --verbose is specified", %{backup_dir: backup_dir} do
      args = ["-r", "EctoBackup.TestPGRepo", "--backup-dir", backup_dir, "--verbose"]
      Mix.Tasks.EctoBackup.Backup.run(args)

      assert_received {:mix_shell, :info,
                       [
                         "\r[EctoBackup.TestPGRepo] pg_dump: dumping contents of " <>
                           "table \"public.test_table_one\""
                       ]}

      assert_received {:mix_shell, :info, ["Backup Summary:"]}
      assert_received {:mix_shell, :info, ["✔ EctoBackup.TestPGRepo" <> _rest]}
      # Mix.Shell.Process.flush(&IO.inspect/1)
    end

    test "handles missing repo configuration gracefully", %{backup_dir: backup_dir} do
      args = ["-r", "NonExistentRepo", "--backup-dir", backup_dir]
      Mix.Tasks.EctoBackup.Backup.run(args)

      assert_received {:mix_shell, :error,
                       ["Configuration Error: NonExistentRepo is not a valid Ecto.Repo module"]}

      # Mix.Shell.Process.flush(&IO.inspect/1)
    end

    test "handles invalid backup directory gracefully" do
      args = ["-r", "EctoBackup.TestPGRepo", "--backup-dir", 12345]
      Mix.Tasks.EctoBackup.Backup.run(args)

      assert_received {:mix_shell, :error,
                       [
                         "Configuration Error: invalid backup " <>
                           "directory path, expected a string, got 12345"
                       ]}
    end

    test "handles invalid backup_file gracefully", %{backup_dir: backup_dir} do
      Application.put_env(:ecto_backup, TestPGRepo, backup_file: "/invalid/path/to/backup.db")
      on_exit(fn -> Application.delete_env(:ecto_backup, TestPGRepo) end)

      args = ["-r", "EctoBackup.TestPGRepo", "--backup-dir", backup_dir]
      Mix.Tasks.EctoBackup.Backup.run(args)

      assert_received {:mix_shell, :error,
                       [
                         "[EctoBackup.TestPGRepo] pg_dump: error: could not open output " <>
                           "file \"/invalid/path/to/backup.db\": No such file or directory"
                       ]}

      assert_received {:mix_shell, :info, ["✘ EctoBackup.TestPGRepo" <> _rest]}
      # Mix.Shell.Process.flush(&IO.inspect/1)
    end

    test "raises on user caused exception", %{backup_dir: backup_dir} do
      Application.put_env(:ecto_backup, TestPGRepo, backup_file: {__MODULE__, :raise_err, []})
      on_exit(fn -> Application.delete_env(:ecto_backup, TestPGRepo) end)
      args = ["-r", "EctoBackup.TestPGRepo", "--backup-dir", backup_dir]

      assert_raise RuntimeError, "Intentional exception for testing", fn ->
        Mix.Tasks.EctoBackup.Backup.run(args)
      end
    end
  end
end
