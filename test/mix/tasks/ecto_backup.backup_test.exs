defmodule Mix.Tasks.EctoBackup.BackupTest do
  use ExUnit.Case
  alias EctoBackup.TestPGRepo
  alias EctoBackup.SecondRepo

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

    Mix.shell(Mix.Shell.Process)

    {:ok, backup_dir: backup_dir}
  end

  describe "run/1" do
    test "successfully backs up a specified repo", %{backup_dir: backup_dir} do
      # Simulate command line arguments
      args = [
        "-r",
        "EctoBackup.TestPGRepo",
        "--backup-dir",
        backup_dir
        # "-v"
      ]

      # Call the Mix task
      # Mix.shell(Mix.Shell.Process)
      Mix.Tasks.EctoBackup.Backup.run(args)

      # Assert the expected behavior
      assert_received {:mix_shell, :info, ["\nBackup Summary:"]}
      assert_received {:mix_shell, :info, ["✔ [EctoBackup.TestPGRepo]" <> _rest]}

      # Mix.Shell.Process.flush(&IO.inspect/1)
    end

    test "successfully backups up a couple default repos", %{backup_dir: backup_dir} do
      Application.put_env(:ecto_backup, :ecto_repos, [TestPGRepo, SecondRepo])
      on_exit(fn -> Application.delete_env(:ecto_backup, :ecto_repos) end)

      Application.put_env(:ecto_backup, :backup_dir, backup_dir)
      on_exit(fn -> Application.delete_env(:ecto_backup, :backup_dir) end)

      # Call the Mix task
      Mix.Tasks.EctoBackup.Backup.run([])

      # Assert the expected behavior
      assert_received {:mix_shell, :info, ["\nBackup Summary:"]}
      assert_received {:mix_shell, :info, ["✔ [EctoBackup.TestPGRepo]" <> rest]}
      assert String.contains?(rest, "✔ [EctoBackup.SecondRepo")

      # Mix.Shell.Process.flush(&IO.inspect/1)
    end

    test "handles missing repo configuration gracefully", %{backup_dir: backup_dir} do
      # Simulate command line arguments with an invalid repo
      args = [
        "-r",
        "NonExistentRepo",
        "--backup-dir",
        backup_dir
      ]

      # Call the Mix task
      Mix.Tasks.EctoBackup.Backup.run(args)

      # Mix.Shell.Process.flush(&IO.inspect/1)

      # Assert the expected error behavior
      assert_received {:mix_shell, :error,
                       ["Configuration Error: NonExistentRepo is not a valid Ecto.Repo module"]}
    end

    test "handles invalid backup directory gracefully" do
      # Simulate command line arguments with an invalid backup directory
      args = [
        "-r",
        "EctoBackup.TestPGRepo",
        "--backup-dir",
        12345
      ]

      # Call the Mix task
      Mix.Tasks.EctoBackup.Backup.run(args)

      # Assert the expected error behavior
      assert_received {:mix_shell, :error,
                       [
                         "Configuration Error: invalid backup " <>
                           "directory path, expected a string, got 12345"
                       ]}
    end

    test "handles invalid backup_file gracefully", %{backup_dir: backup_dir} do
      Application.put_env(:ecto_backup, TestPGRepo, backup_file: "/invalid/path/to/backup.db")
      on_exit(fn -> Application.delete_env(:ecto_backup, TestPGRepo) end)

      # Simulate command line arguments with an invalid backup file
      args = [
        "-r",
        "EctoBackup.TestPGRepo",
        "--backup-dir",
        backup_dir
      ]

      # Call the Mix task
      Mix.Tasks.EctoBackup.Backup.run(args)

      # Assert the expected error behavior
      assert_received {:mix_shell, :error,
                       [
                         "[EctoBackup.TestPGRepo] pg_dump: error: could not open output " <>
                           "file \"/invalid/path/to/backup.db\": No such file or directory"
                       ]}

      assert_received {:mix_shell, :info, ["✘ [EctoBackup.TestPGRepo]" <> _rest]}

      # Mix.Shell.Process.flush(&IO.inspect/1)
    end
  end
end
