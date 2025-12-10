defmodule EctoBackup.ReleaseTest do
  use ExUnit.Case

  alias EctoBackup.TestRepo

  # NOTE: The release module uses the same code as the Mix tasks, so we only do a few basic tests
  # here to ensure the release functions work as expected.

  setup_all do
    # Create a temporary directory for backups
    Temp.track!()
    backup_dir = Temp.mkdir!(prefix: "ecto_backup_test_")
    # backup_dir = "local/backups"

    {:ok, backup_dir: backup_dir}
  end

  setup do
    # Configure the TestRepos to use the StubAdapter for all tests
    Application.put_env(:ecto_backup, EctoBackup.TestRepo, adapter: EctoBackup.StubAdapter)
    Application.put_env(:ecto_backup, EctoBackup.SecondTestRepo, adapter: EctoBackup.StubAdapter)
    on_exit(fn -> Application.delete_env(:ecto_backup, EctoBackup.TestRepo) end)
    on_exit(fn -> Application.delete_env(:ecto_backup, EctoBackup.SecondTestRepo) end)

    # Set the CLI shell to Process to send messages to the test process
    EctoBackup.CLI.shell(EctoBackup.CLI.Shell.Process)

    # Ensure no leftover messages in the inbox before each test
    EctoBackup.CLI.Shell.Process.flush()

    :ok
  end

  describe "backup/1" do
    test "successfully backups up a specified repo" do
      args = "-r EctoBackup.TestRepo --backup-dir local/backups --verbose"
      EctoBackup.Release.backup(args)
      assert_receive {:ecto_backup_shell, :info, "Backup Summary:\n" <> rest}
      assert String.contains?(rest, "✔ EctoBackup.TestRepo")
    end

    test "successfully backs up in quiet mode" do
      args = "-r EctoBackup.TestRepo --backup-dir local/backups --quiet"
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
      backup_file = Path.join(backup_dir, "test_backup_#{System.unique_integer([:positive])}.db")
      {:ok, _results} = EctoBackup.backup(repos: [{TestRepo, [backup_file: backup_file]}])

      {:ok, backup_file: backup_file}
    end

    test "successfully restores a specified repo", %{backup_file: backup_file} do
      args = "#{backup_file} -r EctoBackup.TestRepo --confirm"
      EctoBackup.Release.restore(args)

      assert_received {:ecto_backup_shell, :info, "Restore summary:\n" <> rest}
      assert rest =~ "✔ EctoBackup.TestRepo: Restored successfully"
    end

    test "successfully restores in quiet mode", %{backup_file: backup_file} do
      args = "#{backup_file} -r EctoBackup.TestRepo --confirm --quiet"
      EctoBackup.Release.restore(args)

      refute_receive {:ecto_backup_shell, :info, _msg}
      refute_receive {:ecto_backup_shell, :error, _msg}
    end

    test "handles non existent backup file gracefully", %{backup_file: _backup_file} do
      invalid_file = "non_existent_backup_file.db"
      args = "#{invalid_file} -r EctoBackup.TestRepo --confirm"
      assert catch_exit(EctoBackup.Release.restore(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, error}
      assert error =~ "Restore file is invalid or inaccessible"
    end

    test "handles invalid backup file gracefully", %{backup_dir: backup_dir} do
      # Create an invalid backup file
      invalid_file = Path.join(backup_dir, "invalid_backup.db")
      File.write!(invalid_file, "not a valid db backup")

      args = "#{invalid_file} -r EctoBackup.TestRepo --confirm"
      assert catch_exit(EctoBackup.Release.restore(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, "Restore completed with errors:" <> rest}
      assert rest =~ "✘ EctoBackup.TestRepo"
    end

    test "formats generic exceptions", %{backup_file: backup_file} do
      args = "#{backup_file} --invalid-option -r EctoBackup.TestRepo --confirm"
      assert catch_exit(EctoBackup.Release.restore(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, error}
      assert error =~ "** (OptionParser) Error:"
      assert error =~ "--invalid-option : Unknown option"
    end
  end
end
