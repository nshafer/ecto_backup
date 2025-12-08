defmodule EctoBackup.IOTest do
  use ExUnit.Case
  use Patch
  alias EctoBackup.TestPGRepo
  alias EctoBackup.SecondPGRepo
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

      assert :ok = CLI.info(TestRepo, "This is a repo info message")
      assert_received {:ecto_backup_shell, :info, "[TestRepo] This is a repo info message"}
    end

    test "prints warning message" do
      assert :ok == CLI.warning("This is a warning message")
      assert_received {:ecto_backup_shell, :warning, "This is a warning message"}

      assert :ok = CLI.warning(TestRepo, "This is a repo warning message")
      assert_received {:ecto_backup_shell, :warning, "[TestRepo] This is a repo warning message"}
    end

    test "prints error message" do
      assert :ok == CLI.error("This is an error message")
      assert_received {:ecto_backup_shell, :error, "This is an error message"}

      assert :ok = CLI.error(TestRepo, "This is a repo error message")
      assert_received {:ecto_backup_shell, :error, "[TestRepo] This is a repo error message"}
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
      exception = EctoBackup.ConfError.exception("Invalid configuration")
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
        "EctoBackup.TestPGRepo",
        "--repo",
        "AnotherRepo",
        "--backup-dir",
        "/tmp/backups",
        "-v"
      ]

      options = CLI.parse_backup_args!(args)
      assert options[:repos] == [TestPGRepo, AnotherRepo]
      assert options[:backup_dir] == "/tmp/backups"
      assert options[:verbose] == true
    end
  end

  describe "summarize_backup_results/1" do
    test "prints summary when all backups succeed" do
      results = [
        {:ok, TestPGRepo, "/path/to/backup1.sql"},
        {:ok, SecondPGRepo, "/path/to/backup2.sql"}
      ]

      CLI.summarize_backup_results(results)

      assert_received {:ecto_backup_shell, :info, "Backup Summary:\n" <> rest}
      assert rest =~ "✔ EctoBackup.TestPGRepo"
      assert rest =~ "✔ EctoBackup.SecondPGRepo"
    end

    test "prints error summary when some backups fail" do
      results = [
        {:ok, TestPGRepo, "/path/to/backup1.sql"},
        {:error, SecondPGRepo, EctoBackup.Error.exception("Connection failed")}
      ]

      CLI.summarize_backup_results(results)

      assert_received {:ecto_backup_shell, :error,
                       "Some backups completed with errors:\n" <> rest}

      assert rest =~ "✔ EctoBackup.TestPGRepo: /path/to/backup1.sql"
      assert rest =~ "✘ EctoBackup.SecondPGRepo: Connection failed"
    end
  end

  describe "exit_if_errors/2" do
    test "exits when there are errors in results" do
      results = [
        {:ok, TestPGRepo, "/path/to/backup1.sql"},
        {:error, SecondPGRepo, EctoBackup.Error.exception("Connection failed")}
      ]

      assert catch_exit(CLI.exit_if_errors(results)) == {:shutdown, 1}
      assert catch_exit(CLI.exit_if_errors(results, 99)) == {:shutdown, 99}
    end

    test "does not exit when all backups succeed" do
      results = [
        {:ok, TestPGRepo, "/path/to/backup1.sql"},
        {:ok, SecondPGRepo, "/path/to/backup2.sql"}
      ]

      assert nil == CLI.exit_if_errors(results, 99)
    end
  end

  describe "format_progress/4" do
    test "formats progress bar with subject and label" do
      progress_bar = CLI.format_progress("EctoBackup.TestPGRepo", 15, 36, "MiB", 70)
      str = IO.ANSI.format(progress_bar, false) |> IO.chardata_to_string()
      assert str == "EctoBackup.TestPGRepo         15/36 MiB [#########-------------]  41% "
    end

    test "formats progress bar without label" do
      progress_bar = CLI.format_progress("EctoBackup.TestPGRepo", 45, 145, nil, 70)
      str = IO.ANSI.format(progress_bar, false) |> IO.chardata_to_string()
      assert str == "EctoBackup.TestPGRepo            45/145 [######----------------]  31% "
    end

    test "formats progress bar with long subject and label" do
      subject = "A long subject that exceeds the space available for subjects"
      progress_bar = CLI.format_progress(subject, 300, 1000, "GB", 70)
      str = IO.ANSI.format(progress_bar, false) |> IO.chardata_to_string()

      assert str == "A long subject that exceeds 300/1000 GB [######----------------]  30% "
    end
  end

  describe "timestamp/0" do
    test "returns current timestamp in HH:MM:SS.mmm format" do
      timestamp = CLI.timestamp()
      assert Regex.match?(~r/^\d{2}:\d{2}:\d{2}\.\d{3}$/, timestamp)
    end
  end

  describe "duration/1" do
    test "formats from native time" do
      duration = System.convert_time_unit(512, :millisecond, :native)
      assert CLI.duration(duration) == "512ms"

      duration = System.convert_time_unit(1534, :millisecond, :native)
      assert CLI.duration(duration) == "1.53s"

      duration = System.convert_time_unit(65_478, :millisecond, :native)
      assert CLI.duration(duration) == "1m 5.48s"

      duration = System.convert_time_unit(3_660_250, :millisecond, :native)
      assert CLI.duration(duration) == "1h 1m 0.25s"
    end

    test "formats duration in milliseconds to human-readable string" do
      assert CLI.duration(500, :millisecond) == "500ms"
      assert CLI.duration(1500, :millisecond) == "1.5s"
      assert CLI.duration(65_000, :millisecond) == "1m 5.0s"
      assert CLI.duration(65_100, :millisecond) == "1m 5.1s"
      assert CLI.duration(65_150, :millisecond) == "1m 5.15s"
      assert CLI.duration(3_600_000, :millisecond) == "1h 0m 0.0s"
      assert CLI.duration(3_600_150, :millisecond) == "1h 0m 0.15s"
      assert CLI.duration(3_660_500, :millisecond) == "1h 1m 0.5s"
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

  describe "cmd/2" do
    test "executes command and captures output" do
      {output, 0} = CLI.cmd("echo 'Hello'\necho 'World'")
      assert output == "Hello\nWorld\n"
    end

    test "executes command with custom into" do
      {output, 0} = CLI.cmd("echo 'Hello'\nsleep 0.1\necho 'World'", into: [])
      assert output == ["Hello\n", "World\n"]
      {output, 0} = CLI.cmd("echo 'Hello'\necho 'World'", into: [], lines: 1024)
      assert output == ["Hello", "World"]

      assert_raise(ArgumentError, fn ->
        CLI.cmd("echo 'Hello World'", into: nil)
      end)

      on_output = fn data ->
        send(self(), {:cmd_output, data})
      end

      {output, 0} = CLI.cmd("echo 'Hello\nWorld'", on_output: on_output, into: [], lines: 1024)
      assert_received {:cmd_output, "Hello"}
      assert_received {:cmd_output, "World"}
      assert output == ["Hello", "World"]

      on_output = fn acc, data ->
        send(self(), {:cmd_output, data})
        [data | acc]
      end

      {output, 0} =
        CLI.cmd("echo 'Hello\nWorld'", on_output: {[], on_output}, into: [], lines: 1024)

      assert_received {:cmd_output, "Hello"}
      assert_received {:cmd_output, "World"}
      assert output == ["Hello", "World"]
    end

    test "executes command with on_output callback" do
      on_output = fn data ->
        send(self(), {:cmd_output, data})
      end

      {output, 0} = CLI.cmd("echo 'Hello'\nsleep 0.1\necho 'World'", on_output: on_output)
      assert_received {:cmd_output, "Hello\n"}
      assert_received {:cmd_output, "World\n"}
      assert output == "Hello\nWorld\n"

      {output, 0} = CLI.cmd("echo 'Hello World'", on_output: on_output, into: nil)
      assert_received {:cmd_output, "Hello World\n"}
      assert output == nil

      on_output = fn acc, data ->
        send(self(), {:cmd_output, data})
        [data | acc]
      end

      {output, 0} = CLI.cmd("echo 'Hello World'", on_output: {[], on_output}, into: nil)
      assert_received {:cmd_output, "Hello World\n"}
      assert output == nil
    end

    test "executes command that fails" do
      {output, exit_status} = CLI.cmd({"sh", ["invalid_file"]})
      assert exit_status != 0
      assert output =~ "invalid_file: No such file or directory"
    end

    test "overrides on_output callback if quiet option is set" do
      on_output = fn data ->
        send(self(), {:cmd_output, data})
      end

      {output, 0} =
        CLI.cmd("echo 'Hello'\necho 'World'", on_output: on_output, quiet: true)

      refute_received {:cmd_output, _}
      assert output == "Hello\nWorld\n"
    end
  end
end
