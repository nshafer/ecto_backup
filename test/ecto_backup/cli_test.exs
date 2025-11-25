defmodule EctoBackup.IOTest do
  use ExUnit.Case
  use Patch
  alias EctoBackup.TestPGRepo
  alias EctoBackup.CLI

  doctest EctoBackup.CLI

  describe "logging functions" do
    setup do
      # Set the CLI shell to Process to send messages to the test process
      EctoBackup.CLI.shell(EctoBackup.CLI.Shell.Process)

      # Ensure no leftover messages in the inbox before each test
      EctoBackup.CLI.Shell.Process.flush()
      :ok
    end

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
end
