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
end
