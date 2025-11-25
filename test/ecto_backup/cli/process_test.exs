defmodule EctoBackup.CLI.Shell.ProcessTest do
  use ExUnit.Case
  import EctoBackup.CLI.Shell.Process

  test "process shell sends messages to myself" do
    info("Test message")
    assert_received {:ecto_backup_shell, :info, "Test message"}

    warning("Test warning")
    assert_received {:ecto_backup_shell, :warning, "Test warning"}

    error("Test error")
    assert_received {:ecto_backup_shell, :error, "Test error"}

    status("Test status")
    assert_received {:ecto_backup_shell, :status, "Test status"}
  end

  test "status(nil) does not send a message" do
    status(nil)
    refute_received {:ecto_backup_shell, :status, _}
  end

  test "flush/1 removes all messages from inbox" do
    info("Test message")
    flush()
    refute_received {:ecto_backup_shell, _, _}
  end
end
