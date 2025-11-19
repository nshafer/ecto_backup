defmodule EctoBackup.IOTest do
  use ExUnit.Case
  alias EctoBackup.TestPGRepo
  alias EctoBackup.CLI

  doctest EctoBackup.CLI

  describe "parse_args!/1" do
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

      options = CLI.parse_args!(args)
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
end
