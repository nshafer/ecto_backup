defmodule EctoBackup.IOTest do
  use ExUnit.Case
  use Patch
  alias EctoBackup.TestRepo
  alias EctoBackup.SecondTestRepo
  alias EctoBackup.CLI

  doctest EctoBackup.CLI

  setup do
    # Set the CLI shell to Process to send messages to the test process
    EctoBackup.CLI.shell(EctoBackup.CLI.Shell.Process)

    # Ensure no leftover messages in the inbox before each test
    EctoBackup.CLI.Shell.Process.flush()

    :ok
  end

  describe "logging functions" do
    test "prints info message" do
      assert :ok == CLI.info("This is an info message")
      assert_received {:ecto_backup_shell, :info, "This is an info message"}

      assert :ok = CLI.info(Repo, "This is a repo info message")
      assert_received {:ecto_backup_shell, :info, "[Repo] This is a repo info message"}
    end

    test "prints warning message" do
      assert :ok == CLI.warning("This is a warning message")
      assert_received {:ecto_backup_shell, :warning, "This is a warning message"}

      assert :ok = CLI.warning(Repo, "This is a repo warning message")
      assert_received {:ecto_backup_shell, :warning, "[Repo] This is a repo warning message"}
    end

    test "prints error message" do
      assert :ok == CLI.error("This is an error message")
      assert_received {:ecto_backup_shell, :error, "This is an error message"}

      assert :ok = CLI.error(Repo, "This is a repo error message")
      assert_received {:ecto_backup_shell, :error, "[Repo] This is a repo error message"}
    end
  end

  describe "fatal/2" do
    test "fatal with string message exits with default status" do
      assert catch_exit(CLI.fatal("Fatal error occurred")) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error,
                       "** (EctoBackup) Fatal error: Fatal error occurred"}
    end

    test "fatal with string message exits with custom status" do
      assert catch_exit(CLI.fatal("Fatal error occurred", 42)) == {:shutdown, 42}

      assert_received {:ecto_backup_shell, :error,
                       "** (EctoBackup) Fatal error: Fatal error occurred"}
    end

    test "fatal with EctoBackup.Error exception" do
      exception = EctoBackup.Error.exception("Something went wrong")
      assert catch_exit(CLI.fatal(exception)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error,
                       "** (EctoBackup) Fatal error: Something went wrong"}
    end

    test "fatal with EctoBackup.ConfError exception" do
      exception =
        EctoBackup.ConfError.exception(
          reason: :invalid_configuration,
          message: "Invalid configuration"
        )

      assert catch_exit(CLI.fatal(exception)) == {:shutdown, 1}

      assert_received {:ecto_backup_shell, :error,
                       "** (EctoBackup) Configuration error: Invalid configuration"}
    end

    test "fatal with other exception type" do
      exception = RuntimeError.exception("Runtime error")
      assert catch_exit(CLI.fatal(exception)) == {:shutdown, 1}
      assert_received {:ecto_backup_shell, :error, "** (RuntimeError) Error: Runtime error"}
    end

    test "sets progress bar as status" do
      assert :ok == CLI.progress("This is a status message", 10, 100, "MiB", 70)
      status = "This is a status message     10/100 MiB [##--------------------]  10% "
      assert_received {:ecto_backup_shell, :status, ^status}
    end
  end

  describe "parse_backup_args!/1" do
    test "parses command line arguments into options map" do
      args = [
        "-r",
        "EctoBackup.TestRepo",
        "--repo",
        "EctoBackup.SecondTestRepo",
        "--backup-dir",
        "/tmp/backups",
        "-v"
      ]

      options = CLI.parse_backup_args!(args)
      assert options[:repos] == [TestRepo, SecondTestRepo]
      assert options[:backup_dir] == "/tmp/backups"
      assert options[:verbose] == true
    end
  end

  describe "parse_restore_args!/1" do
    test "parses command line arguments into options map" do
      args = [
        "-r",
        "EctoBackup.TestRepo",
        "-f",
        "testrepo_backup.db",
        "--repo",
        "EctoBackup.SecondTestRepo",
        "--file",
        "secondtestrepo_backup.db",
        "--restore-dir",
        "/tmp/backups",
        "-v"
      ]

      options = CLI.parse_restore_args!(args)
      assert options[:repos] == [TestRepo, SecondTestRepo]
      assert options[:files] == ["testrepo_backup.db", "secondtestrepo_backup.db"]
      assert options[:restore_dir] == "/tmp/backups"
      assert options[:verbose] == true
    end
  end

  describe "summarize_backup_results/1" do
    test "prints summary when all backups succeed" do
      results = [
        {:ok, TestRepo, "/path/to/backup1.db"},
        {:ok, SecondTestRepo, "/path/to/backup2.db"}
      ]

      CLI.summarize_backup_results(results)

      assert_received {:ecto_backup_shell, :info, "Backup Summary:\n" <> rest}
      assert rest =~ "✔ EctoBackup.TestRepo"
      assert rest =~ "✔ EctoBackup.SecondTestRepo"
    end

    test "prints error summary when some backups fail" do
      results = [
        {:ok, TestRepo, "/path/to/backup1.db"},
        {:error, SecondTestRepo, EctoBackup.Error.exception("Connection failed")}
      ]

      CLI.summarize_backup_results(results)

      assert_received {:ecto_backup_shell, :error,
                       "Some backups completed with errors:\n" <> rest}

      assert rest =~ "✔ EctoBackup.TestRepo: /path/to/backup1.db"
      assert rest =~ "✘ EctoBackup.SecondTestRepo: Connection failed"
    end
  end

  describe "summarize_restore_results/1" do
    test "prints success message on successful restore" do
      results = [
        {:ok, TestRepo, "/path/to/restore1.db"},
        {:ok, SecondTestRepo, "/path/to/restore2.db"}
      ]

      CLI.summarize_restore_results(results)

      assert_received {:ecto_backup_shell, :info, "Restore Summary:\n" <> rest}
      assert rest =~ "✔ EctoBackup.TestRepo: /path/to/restore1.db"
      assert rest =~ "✔ EctoBackup.SecondTestRepo: /path/to/restore2.db"
    end

    test "prints error message on failed restore" do
      results = [
        {:ok, TestRepo, "/path/to/backup1.db"},
        {:error, SecondTestRepo, EctoBackup.Error.exception("Connection failed")}
      ]

      CLI.summarize_restore_results(results)

      assert_received {:ecto_backup_shell, :error,
                       "Some restores completed with errors:\n" <> rest}

      assert rest =~ "✔ EctoBackup.TestRepo: /path/to/backup1.db"
      assert rest =~ "✘ EctoBackup.SecondTestRepo: Connection failed"
    end
  end

  describe "exit_if_errors/2" do
    test "exits when there are errors in results" do
      results = [
        {:ok, TestRepo, "/path/to/backup1.db"},
        {:error, SecondTestRepo, EctoBackup.Error.exception("Connection failed")}
      ]

      assert catch_exit(CLI.exit_if_errors(results)) == {:shutdown, 1}
      assert catch_exit(CLI.exit_if_errors(results, 99)) == {:shutdown, 99}
    end

    test "does not exit when all backups succeed" do
      results = [
        {:ok, TestRepo, "/path/to/backup1.db"},
        {:ok, SecondTestRepo, "/path/to/backup2.db"}
      ]

      assert nil == CLI.exit_if_errors(results, 99)
    end
  end

  describe "format_progress/4" do
    test "formats progress bar with subject and label" do
      progress_bar = CLI.format_progress("EctoBackup.TestRepo", 15, 36, "MiB", 70)
      str = IO.ANSI.format(progress_bar, false) |> IO.chardata_to_string()
      assert str == "EctoBackup.TestRepo           15/36 MiB [#########-------------]  41% "
    end

    test "formats progress bar without label" do
      progress_bar = CLI.format_progress("EctoBackup.TestRepo", 45, 145, nil, 70)
      str = IO.ANSI.format(progress_bar, false) |> IO.chardata_to_string()
      assert str == "EctoBackup.TestRepo              45/145 [######----------------]  31% "
    end

    test "formats progress bar with long subject and label" do
      subject = "A long subject that exceeds the space available for subjects"
      progress_bar = CLI.format_progress(subject, 300, 1000, "GB", 70)
      str = IO.ANSI.format(progress_bar, false) |> IO.chardata_to_string()

      assert str == "A long subject that exceeds 300/1000 GB [######----------------]  30% "
    end
  end

  describe "term_width/0" do
    test "returns terminal width as integer" do
      width = CLI.term_width()
      assert is_integer(width)
      assert width > 0
    end

    test "returns 80 when terminal width cannot be determined" do
      # Simulate failure to get terminal width by temporarily overriding :io.columns/0
      patch(:io, :columns, fn -> :error end)
      width = CLI.term_width()
      assert is_integer(width)
      assert width == 80
    end

    test "returns actual terminal width when available" do
      # Simulate successful retrieval of terminal width
      patch(:io, :columns, fn -> {:ok, 100} end)
      width = CLI.term_width()
      assert is_integer(width)
      assert width == 100
    end
  end

  describe "confirm_restore/2" do
    test "prompts user for confirmation before restore" do
      repo_config = %{database: "test_db", restore_file: "/path/to/backup.db"}

      send(self(), {:ecto_backup_shell_input, :prompt, inspect(TestRepo)})
      assert CLI.confirm_restore(TestRepo, repo_config) == true
      assert_received {:ecto_backup_shell, :prompt, prompt}
      assert prompt =~ "Please type the name of the repository to confirm"

      send(self(), {:ecto_backup_shell_input, :prompt, "no"})
      assert CLI.confirm_restore(TestRepo, repo_config) == false
      assert_received {:ecto_backup_shell, :prompt, prompt}
      assert prompt =~ "Please type the name of the repository to confirm"

      send(self(), {:ecto_backup_shell_input, :prompt, ""})
      assert CLI.confirm_restore(TestRepo, repo_config) == false
      assert_received {:ecto_backup_shell, :prompt, prompt}
      assert prompt =~ "Please type the name of the repository to confirm"
    end
  end
end
