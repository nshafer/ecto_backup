defmodule EctoBackup.ReleaseTest do
  use ExUnit.Case

  alias EctoBackup.TestPGRepo

  # NOTE: The release module uses the same code as the Mix tasks, so we only do a few basic tests
  # here to ensure the release functions work as expected.

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
    # Set the CLI shell to Process to send messages to the test process
    EctoBackup.CLI.shell(EctoBackup.CLI.Shell.Process)

    # Ensure no leftover messages in the inbox before each test
    EctoBackup.CLI.Shell.Process.flush()

    :ok
  end

  describe "backup/1" do
    test "successfully backups up a specified repo" do
      args = "-r EctoBackup.TestPGRepo --backup-dir local/backups --verbose"
      EctoBackup.Release.backup(args)
      assert_receive {:ecto_backup_shell, :info, "Backup Summary:\n" <> rest}
      assert String.contains?(rest, "✔ EctoBackup.TestPGRepo")
    end

    test "successfully backs up in quiet mode" do
      args = "-r EctoBackup.TestPGRepo --backup-dir local/backups --quiet"
      EctoBackup.Release.backup(args)
      refute_receive {:ecto_backup_shell, :info, _msg}
      refute_receive {:ecto_backup_shell, :error, _msg}
    end

    test "returns error on invalid repo" do
      args = "-r NonExistent.Repo --backup-dir local/backups"
      assert catch_exit(EctoBackup.Release.backup(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, error}
      assert error =~ "NonExistent.Repo is not a valid Ecto.Repo module"
    end

    test "formats generic exceptions" do
      args = "--invalid-option"
      assert catch_exit(EctoBackup.Release.backup(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, error}
      assert error =~ "** (OptionParser) Error:"
      assert error =~ "--invalid-option : Unknown option"
    end
  end

  describe "restore/1" do
    setup %{backup_dir: backup_dir} do
      # Create a backup file for restore tests using the backup task
      backup_file = Path.join(backup_dir, "test_backup_#{System.unique_integer([:positive])}.sql")

      {:ok, _results} =
        EctoBackup.backup(%{
          repos: [{TestPGRepo, [backup_file: backup_file]}],
          backup_dir: backup_dir
        })

      {:ok, backup_file: backup_file}
    end

    test "successfully restores a specified repo", %{backup_file: backup_file} do
      args = "#{backup_file} -r EctoBackup.TestPGRepo --confirm"
      EctoBackup.Release.restore(args)

      assert_received {:ecto_backup_shell, :info, "Restore summary:\n" <> rest}
      assert rest =~ "✔ EctoBackup.TestPGRepo: Restored successfully"
    end

    test "successfully restores in quiet mode", %{backup_file: backup_file} do
      args = "#{backup_file} -r EctoBackup.TestPGRepo --confirm --quiet"
      EctoBackup.Release.restore(args)

      refute_receive {:ecto_backup_shell, :info, _msg}
      refute_receive {:ecto_backup_shell, :error, _msg}
    end

    test "handles non existent backup file gracefully", %{backup_file: _backup_file} do
      invalid_file = "non_existent_backup_file.sql"
      args = "#{invalid_file} -r EctoBackup.TestPGRepo --confirm"
      assert catch_exit(EctoBackup.Release.restore(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, error}
      assert error =~ "Restore file is invalid or inaccessible"
    end

    test "handles invalid backup file gracefully", %{backup_file: backup_file} do
      # Create an invalid backup file
      invalid_file = Path.join(Path.dirname(backup_file), "invalid_backup.db")
      File.write!(invalid_file, "not a valid db backup")

      args = "#{invalid_file} -r EctoBackup.TestPGRepo --confirm"
      assert catch_exit(EctoBackup.Release.restore(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, "Restore completed with errors:" <> rest}
      assert rest =~ "✘ EctoBackup.TestPGRepo"
    end

    test "formats generic exceptions", %{backup_file: backup_file} do
      args = "#{backup_file} --invalid-option -r EctoBackup.TestPGRepo --confirm"
      assert catch_exit(EctoBackup.Release.restore(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, error}
      assert error =~ "** (OptionParser) Error:"
      assert error =~ "--invalid-option : Unknown option"
    end
  end
end
