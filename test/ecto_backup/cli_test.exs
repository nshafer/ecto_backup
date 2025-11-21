defmodule EctoBackup.IOTest do
  use ExUnit.Case
  alias EctoBackup.TestPGRepo
  alias EctoBackup.CLI

  doctest EctoBackup.CLI

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

  describe "format_log/2" do
    test "formats log messages with ANSI codes" do
      log_message = CLI.format_log(:info, "Backup started")
      assert is_list(log_message)
      log_message = List.flatten(log_message)
      assert Enum.any?(log_message, fn code -> code == :default_color end)
      assert Enum.any?(log_message, fn msg -> msg == "Backup started" end)

      log_message = CLI.format_log(:warning, "Backup warning")
      assert is_list(log_message)
      log_message = List.flatten(log_message)
      assert Enum.any?(log_message, fn code -> code == :yellow end)
      assert Enum.any?(log_message, fn msg -> msg == "Backup warning" end)

      log_message = CLI.format_log(:error, "Backup failed")
      assert is_list(log_message)
      log_message = List.flatten(log_message)
      assert Enum.any?(log_message, fn code -> code == :red end)
      assert Enum.any?(log_message, fn msg -> msg == "Backup failed" end)

      log_message = CLI.format_log(:debug, "Debug message")
      assert is_list(log_message)
      log_message = List.flatten(log_message)
      assert Enum.any?(log_message, fn code -> code == :default_color end)
      assert Enum.any?(log_message, fn msg -> msg == "Debug message" end)
    end
  end

  describe "format_progress/4" do
    test "formats progress bar with subject and label" do
      progress_bar = CLI.format_progress("EctoBackup.TestPGRepo", 15, 36, "MiB", 70)
      str = IO.ANSI.format(progress_bar, false) |> IO.chardata_to_string()
      assert str == "\rEctoBackup.TestPGRepo         15/36 MiB [#########-------------]  41% "
    end

    test "formats progress bar without label" do
      progress_bar = CLI.format_progress("EctoBackup.TestPGRepo", 45, 145, nil, 70)
      str = IO.ANSI.format(progress_bar, false) |> IO.chardata_to_string()
      assert str == "\rEctoBackup.TestPGRepo            45/145 [######----------------]  31% "
    end

    test "formats progress bar with long subject and label" do
      subject = "A long subject that exceeds the space available for subjects"
      progress_bar = CLI.format_progress(subject, 300, 1000, "GB", 70)
      str = IO.ANSI.format(progress_bar, false) |> IO.chardata_to_string()

      assert str == "\rA long subject that exceeds 300/1000 GB [######----------------]  30% "
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
end
