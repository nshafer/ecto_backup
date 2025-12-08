defmodule Mix.Tasks.EctoBackup.RestoreTest do
  use ExUnit.Case
  alias EctoBackup.TestPGRepo
  alias EctoBackup.SecondPGRepo

  setup_all do
    # Create test database for all tests in this module
    TestPGRepo.create_db()
    start_supervised!(TestPGRepo)
    TestPGRepo.create_default_tables()
    TestPGRepo.insert_test_data(10)
    on_exit(fn -> TestPGRepo.drop_db() end)

    Temp.track!()
    backup_dir = Temp.mkdir!(prefix: "ecto_backup_restore_test_")

    {:ok, backup_dir: backup_dir}
  end

  setup %{backup_dir: backup_dir} do
    # Set the CLI shell to Process to send messages to the test process
    EctoBackup.CLI.shell(EctoBackup.CLI.Shell.Process)

    # Ensure no leftover messages in the inbox before each test
    EctoBackup.CLI.Shell.Process.flush()

    # Create a backup file for restore tests using the backup task
    backup_file = Path.join(backup_dir, "test_backup_#{System.unique_integer([:positive])}.db")

    {:ok, _results} =
      EctoBackup.backup(%{
        repos: [{TestPGRepo, [backup_file: backup_file]}],
        backup_dir: backup_dir
      })

    {:ok, backup_file: backup_file}
  end

  def raise_err(_repo, _repo_config, _restore_file, _options) do
    raise "Intentional exception for testing"
  end

  describe "run/1" do
    test "successfully restores a specified repo with --confirm flag", %{backup_file: backup_file} do
      args = [backup_file, "-r", "EctoBackup.TestPGRepo", "--confirm"]
      Mix.Tasks.EctoBackup.Restore.run(args)

      assert_received {:ecto_backup_shell, :info, "Restore summary:\n" <> rest}
      assert rest =~ "✔ EctoBackup.TestPGRepo: Restored successfully"
    end

    test "successfully restores when single repo is configured", %{backup_file: backup_file} do
      Application.put_env(:ecto_backup, :repos, [TestPGRepo])
      on_exit(fn -> Application.delete_env(:ecto_backup, :repos) end)

      args = [backup_file, "--confirm"]
      Mix.Tasks.EctoBackup.Restore.run(args)

      assert_received {:ecto_backup_shell, :info, "Restore summary:\n" <> rest}
      assert rest =~ "✔ EctoBackup.TestPGRepo: Restored successfully"
    end

    test "outputs verbose logs when --verbose is specified", %{backup_file: backup_file} do
      args = [backup_file, "-r", "EctoBackup.TestPGRepo", "--confirm", "--verbose"]
      Mix.Tasks.EctoBackup.Restore.run(args)

      assert_received {:ecto_backup_shell, :info,
                       "[EctoBackup.TestPGRepo] pg_restore: processing data for table " <> _}

      assert_received {:ecto_backup_shell, :info, "Restore summary:\n" <> rest}
      assert rest =~ "✔ EctoBackup.TestPGRepo: Restored successfully"
    end

    test "handles missing repo configuration gracefully", %{backup_file: backup_file} do
      args = [backup_file, "-r", "NonExistentRepo", "--confirm"]
      assert catch_exit(Mix.Tasks.EctoBackup.Restore.run(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, msg}
      assert msg =~ "NonExistentRepo is not a valid Ecto.Repo module"
    end

    test "handles missing restore file gracefully" do
      args = ["/nonexistent/backup_file.db", "-r", "EctoBackup.TestPGRepo", "--confirm"]
      assert catch_exit(Mix.Tasks.EctoBackup.Restore.run(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, msg}
      assert msg =~ "Restore file is invalid or inaccessible"
    end

    test "handles missing restore file argument gracefully" do
      args = ["-r", "EctoBackup.TestPGRepo", "--confirm"]

      assert_raise OptionParser.ParseError, "restore_file argument is required", fn ->
        Mix.Tasks.EctoBackup.Restore.run(args)
      end
    end

    test "handles invalid restore file gracefully", %{backup_dir: backup_dir} do
      # Create an invalid restore file (empty file)
      invalid_file = Path.join(backup_dir, "invalid.db")
      File.write!(invalid_file, "not a valid db backup")

      args = [invalid_file, "-r", "EctoBackup.TestPGRepo", "--confirm"]
      assert catch_exit(Mix.Tasks.EctoBackup.Restore.run(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, "Restore completed with errors:" <> rest}
      assert rest =~ "✘ EctoBackup.TestPGRepo"
    end

    test "handles multiple repos configured without -r flag", %{backup_file: backup_file} do
      Application.put_env(:ecto_backup, :repos, [TestPGRepo, SecondPGRepo])
      on_exit(fn -> Application.delete_env(:ecto_backup, :repos) end)

      args = [backup_file, "--confirm"]
      assert catch_exit(Mix.Tasks.EctoBackup.Restore.run(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, msg}
      assert msg =~ "multiple repositories"
    end

    test "handles no repos configured without -r flag", %{backup_file: backup_file} do
      Application.put_env(:ecto_backup, :repos, [])
      on_exit(fn -> Application.delete_env(:ecto_backup, :repos) end)

      args = [backup_file, "--confirm"]
      assert catch_exit(Mix.Tasks.EctoBackup.Restore.run(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, msg}
      assert msg =~ "no repositories to restore"
    end

    test "quiet mode suppresses non-error output", %{backup_file: backup_file} do
      args = [backup_file, "-r", "EctoBackup.TestPGRepo", "--confirm", "--quiet"]
      Mix.Tasks.EctoBackup.Restore.run(args)

      refute_received {:ecto_backup_shell, :info, _msg}
      refute_received {:ecto_backup_shell, :warning, _msg}
    end
  end
end
