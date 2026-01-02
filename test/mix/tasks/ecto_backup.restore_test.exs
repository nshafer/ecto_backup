defmodule Mix.Tasks.EctoBackup.RestoreTest do
  use ExUnit.Case
  alias EctoBackup.TestRepo
  alias EctoBackup.SecondTestRepo
  alias EctoBackup.StubAdapter

  def raise_err(_repo, _repo_config, _restore_file, _options) do
    raise "Intentional exception for testing"
  end

  setup_all do
    # Create a temporary directory for backups
    Temp.track!()
    backup_dir = Temp.mkdir!(prefix: "ecto_backup_restore_test_")
    # backup_dir = "local/backups"

    {:ok, backup_dir: backup_dir}
  end

  setup %{backup_dir: backup_dir} do
    # Configure the TestRepos to use the StubAdapter for all tests
    Application.put_env(:ecto_backup, TestRepo, adapter: StubAdapter)
    Application.put_env(:ecto_backup, SecondTestRepo, adapter: StubAdapter)
    on_exit(fn -> Application.delete_env(:ecto_backup, TestRepo) end)
    on_exit(fn -> Application.delete_env(:ecto_backup, SecondTestRepo) end)

    # Set the CLI shell to Process to send messages to the test process
    EctoBackup.CLI.shell(EctoBackup.CLI.Shell.Process)

    # Ensure no leftover messages in the inbox before each test
    EctoBackup.CLI.Shell.Process.flush()

    # Create a backup file for restore tests using the backup task
    backup_file = Path.join(backup_dir, "test_backup_#{System.unique_integer([:positive])}.db")
    {:ok, _results} = EctoBackup.backup(repos: [{TestRepo, [backup_file: backup_file]}])

    {:ok, backup_file: backup_file}
  end

  describe "run/1" do
    test "successfully restores a specified repo with --confirm flag", %{backup_file: backup_file} do
      args = ["-r", "EctoBackup.TestRepo", "-f", backup_file, "--confirm", "EctoBackup.TestRepo"]
      Mix.Tasks.EctoBackup.Restore.run(args)

      assert_received {:ecto_backup_shell, :info, "Restore Summary:\n" <> rest}
      assert rest =~ "✔ EctoBackup.TestRepo: #{backup_file}"
    end

    test "successfully restores the latest backup", %{backup_dir: backup_dir} do
      # Create a backup file with the default naming convention so it will be found
      {:ok, [{:ok, TestRepo, backup_file}]} =
        EctoBackup.backup(repos: [TestRepo], backup_dir: backup_dir)

      args = ["-r", "EctoBackup.TestRepo", "-d", backup_dir, "--confirm", "EctoBackup.TestRepo"]
      Mix.Tasks.EctoBackup.Restore.run(args)
      assert_received {:ecto_backup_shell, :info, "Restore Summary:\n" <> rest}
      assert rest =~ "✔ EctoBackup.TestRepo: #{backup_file}"
    end

    test "successfully restores when single repo is configured", %{backup_file: backup_file} do
      Application.put_env(:ecto_backup, :repos, [TestRepo])
      on_exit(fn -> Application.delete_env(:ecto_backup, :repos) end)

      args = ["-f", backup_file, "--confirm", "EctoBackup.TestRepo"]
      Mix.Tasks.EctoBackup.Restore.run(args)

      assert_received {:ecto_backup_shell, :info, "Restore Summary:\n" <> rest}
      assert rest =~ "✔ EctoBackup.TestRepo: #{backup_file}"
    end

    test "outputs verbose logs when --verbose is specified", %{backup_file: backup_file} do
      args =
        [
          "-r",
          "EctoBackup.TestRepo",
          "-f",
          backup_file,
          "--confirm",
          "EctoBackup.TestRepo",
          "--verbose"
        ]

      Mix.Tasks.EctoBackup.Restore.run(args)
      assert_received {:ecto_backup_shell, :info, "[EctoBackup.TestRepo] restoring stub data"}
      assert_received {:ecto_backup_shell, :info, "Restore Summary:\n" <> rest}
      assert rest =~ "✔ EctoBackup.TestRepo: #{backup_file}"
    end

    test "handles missing repo configuration gracefully", %{backup_file: backup_file} do
      args = ["-r", "NonExistentRepo", "-f", backup_file, "--confirm", "NonExistentRepo"]
      assert catch_exit(Mix.Tasks.EctoBackup.Restore.run(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, msg}
      assert msg =~ "NonExistentRepo is not a valid Ecto.Repo module"
    end

    test "handles missing restore file gracefully" do
      args = [
        "-r",
        "EctoBackup.TestRepo",
        "-f",
        "/nonexistent/backup_file.db",
        "--confirm",
        "EctoBackup.TestRepo"
      ]

      assert catch_exit(Mix.Tasks.EctoBackup.Restore.run(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, msg}

      assert msg =~
               "restore file \"/nonexistent/backup_file.db\" for " <>
                 "repo EctoBackup.TestRepo does not exist"
    end

    test "handles invalid restore file gracefully", %{backup_dir: backup_dir} do
      # Create an invalid restore file (empty file)
      invalid_file = Path.join(backup_dir, "invalid.db")
      File.write!(invalid_file, "not a valid db backup")

      args = ["-r", "EctoBackup.TestRepo", "-f", invalid_file, "--confirm", "EctoBackup.TestRepo"]
      assert catch_exit(Mix.Tasks.EctoBackup.Restore.run(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, "Some restores completed with errors:" <> rest}
      assert rest =~ "✘ EctoBackup.TestRepo"
    end

    test "handles mismatched repos and files lists", %{backup_file: backup_file} do
      args = [
        "-r",
        "EctoBackup.TestRepo",
        "-r",
        "EctoBackup.SecondTestRepo",
        "-f",
        backup_file,
        "--confirm",
        "EctoBackup.TestRepo"
      ]

      assert catch_exit(Mix.Tasks.EctoBackup.Restore.run(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, msg}
      assert msg =~ "mismatched number of repos and restore files provided"
    end

    test "handles mismatched files lists to global repos", %{backup_file: backup_file} do
      Application.put_env(:ecto_backup, :repos, [TestRepo, SecondTestRepo])
      on_exit(fn -> Application.delete_env(:ecto_backup, :repos) end)
      args = ["-f", backup_file, "--confirm", "EctoBackup.TestRepo"]
      assert catch_exit(Mix.Tasks.EctoBackup.Restore.run(args)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error, msg}
      assert msg =~ "mismatched number of repos and restore files provided"
    end

    test "handles no repos configured without -r flag" do
      Application.put_env(:ecto_backup, :repos, [])
      on_exit(fn -> Application.delete_env(:ecto_backup, :repos) end)

      args = []
      assert catch_exit(Mix.Tasks.EctoBackup.Restore.run(args)) == {:shutdown, 1}
      assert_received {:ecto_backup_shell, :error, msg}
      assert msg =~ "no repositories to restore"
    end

    test "quiet mode suppresses non-error output", %{backup_file: backup_file} do
      args = [
        "-r",
        "EctoBackup.TestRepo",
        "-f",
        backup_file,
        "--confirm",
        "EctoBackup.TestRepo",
        "--quiet"
      ]

      Mix.Tasks.EctoBackup.Restore.run(args)

      refute_received {:ecto_backup_shell, :info, _msg}
      refute_received {:ecto_backup_shell, :warning, _msg}
    end
  end
end
