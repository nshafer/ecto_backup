defmodule EctoBackup.CLI.TelemetryTest do
  use ExUnit.Case

  alias EctoBackup.CLI.Telemetry

  setup do
    # Set the CLI shell to Process to send messages to the test process
    EctoBackup.CLI.shell(EctoBackup.CLI.Shell.Process)

    # Ensure no leftover messages in the inbox before each test
    EctoBackup.CLI.Shell.Process.flush()

    :ok
  end

  test "attaches and detaches telemetry handlers" do
    assert :ok = Telemetry.attach(%{})
    assert :ok = Telemetry.detach()
  end

  test "can attach multiple times without error" do
    assert :ok = Telemetry.attach(%{})
    assert :ok = Telemetry.attach(%{})
    assert :ok = Telemetry.detach()
  end

  describe "handle_event/4 for backup events" do
    test "handles backup start event for multiple repos" do
      Telemetry.handle_event(
        [:ecto_backup, :backup, :start],
        %{},
        %{repos: [{Repo1, %{}}, {Repo2, %{}}]},
        %{}
      )

      assert_received {:ecto_backup_shell, :info, message}
      assert message =~ "Starting backups for 2 repositories"
      assert message =~ "Repo1"
      assert message =~ "Repo2"
    end

    test "does not log for single repo backup start event" do
      Telemetry.handle_event(
        [:ecto_backup, :backup, :start],
        %{},
        %{repos: [{Repo1, %{}}]},
        %{}
      )

      refute_received {:ecto_backup_shell, :info, _message}
    end

    test "handles backup stop event for multiple repos" do
      Telemetry.handle_event(
        [:ecto_backup, :backup, :stop],
        %{duration: System.convert_time_unit(5, :second, :native)},
        %{repos: [{Repo1, %{}}, {Repo2, %{}}]},
        %{}
      )

      assert_received {:ecto_backup_shell, :info, message}
      assert message =~ "All backups completed in 5.0s"
    end

    test "does not log for single repo backup stop event" do
      Telemetry.handle_event(
        [:ecto_backup, :backup, :stop],
        %{duration: System.convert_time_unit(3, :second, :native)},
        %{repos: [{Repo1, %{}}]},
        %{}
      )

      refute_received {:ecto_backup_shell, :info, _message}
    end

    test "handles repo start event" do
      Telemetry.handle_event(
        [:ecto_backup, :backup, :repo, :start],
        %{},
        %{repo: Repo1, repo_config: %{database: "repo1"}, backup_file: "/path/to/backup.sql"},
        %{}
      )

      assert_received {:ecto_backup_shell, :info, message}
      assert message =~ "[Repo1] Starting backup"
      assert message =~ "/path/to/backup.sql"
    end

    test "handles repo stop event" do
      Telemetry.handle_event(
        [:ecto_backup, :backup, :repo, :stop],
        %{duration: System.convert_time_unit(2, :second, :native)},
        %{repo: Repo1, repo_config: %{}, backup_file: "/path/to/backup.sql"},
        %{}
      )

      assert_received {:ecto_backup_shell, :info, message}
      assert message =~ "[Repo1] Backup completed in 2.0s"
    end

    test "handles repo progress event" do
      Telemetry.handle_event(
        [:ecto_backup, :backup, :repo, :progress],
        %{completed: 50, total: 200},
        %{repo: Repo1},
        %{}
      )

      assert_received {:ecto_backup_shell, :status, status}
      assert status =~ "Repo1"
      assert status =~ "50/200"
    end

    test "handles repo message errors" do
      Telemetry.handle_event(
        [:ecto_backup, :backup, :repo, :message],
        %{},
        %{repo: Repo1, level: :error, message: "This is a test error"},
        %{}
      )

      assert_received {:ecto_backup_shell, :error, message}
      assert message =~ "[Repo1] Error: This is a test error"
    end

    test "does not output info messages when not verbose" do
      Telemetry.handle_event(
        [:ecto_backup, :backup, :repo, :message],
        %{},
        %{repo: Repo1, level: :info, message: "This is a verbose message"},
        %{verbose: false}
      )

      refute_received {:ecto_backup_shell, :info, _message}
    end

    test "handles repo message event with verbosity" do
      Telemetry.handle_event(
        [:ecto_backup, :backup, :repo, :message],
        %{},
        %{repo: Repo1, level: :info, message: "Verbose message"},
        %{verbose: true}
      )

      assert_received {:ecto_backup_shell, :info, message}
      assert message =~ "[Repo1] Verbose message"
    end
  end

  describe "handle_event/4 for restore events" do
    test "handles restore start event" do
      Telemetry.handle_event(
        [:ecto_backup, :restore, :start],
        %{},
        %{},
        %{}
      )

      # No output expected for restore start
      refute_received {:ecto_backup_shell, :info, _message}
    end

    test "handles restore stop event" do
      Telemetry.handle_event(
        [:ecto_backup, :restore, :stop],
        %{},
        %{},
        %{}
      )

      # No output expected for restore stop
      refute_received {:ecto_backup_shell, :info, _message}
    end

    test "handles repo restore start event" do
      Telemetry.handle_event(
        [:ecto_backup, :restore, :repo, :start],
        %{},
        %{repo: Repo1, repo_config: %{database: "repo1"}, restore_file: "/path/to/restore.sql"},
        %{}
      )

      assert_received {:ecto_backup_shell, :info, message}
      assert message =~ "[Repo1] Starting restore"
      assert message =~ "/path/to/restore.sql"
    end

    test "handles repo restore stop event" do
      Telemetry.handle_event(
        [:ecto_backup, :restore, :repo, :stop],
        %{duration: System.convert_time_unit(4, :second, :native)},
        %{repo: Repo1},
        %{}
      )

      assert_received {:ecto_backup_shell, :info, message}
      assert message =~ "[Repo1] Restore completed in 4.0s"
    end

    test "handles repo restore progress event" do
      Telemetry.handle_event(
        [:ecto_backup, :restore, :repo, :progress],
        %{completed: 75, total: 300},
        %{repo: Repo1},
        %{}
      )

      assert_received {:ecto_backup_shell, :status, status}
      assert status =~ "Repo1"
      assert status =~ "75/300"
    end

    test "handles repo restore message errors" do
      Telemetry.handle_event(
        [:ecto_backup, :restore, :repo, :message],
        %{},
        %{repo: Repo1, level: :error, message: "Restore error occurred"},
        %{}
      )

      assert_received {:ecto_backup_shell, :error, message}
      assert message =~ "[Repo1] Error: Restore error occurred"
    end

    test "does not output info messages during restore when not verbose" do
      Telemetry.handle_event(
        [:ecto_backup, :restore, :repo, :message],
        %{},
        %{repo: Repo1, level: :info, message: "Restore verbose message"},
        %{verbose: false}
      )

      refute_received {:ecto_backup_shell, :info, _message}
    end

    test "handles repo restore message event with verbosity" do
      Telemetry.handle_event(
        [:ecto_backup, :restore, :repo, :message],
        %{},
        %{repo: Repo1, level: :info, message: "Restore verbose message"},
        %{verbose: true}
      )

      assert_received {:ecto_backup_shell, :info, message}
      assert message =~ "[Repo1] Restore verbose message"
    end
  end
end
