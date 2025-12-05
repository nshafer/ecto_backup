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

  test "prompt/1 sends input message to myself" do
    send(self(), {:ecto_backup_shell_input, :prompt, "User input"})
    input = prompt("Enter something:")
    assert input == "User input"
    assert_received {:ecto_backup_shell, :prompt, "Enter something:"}
  end

  test "raises if no input message is received" do
    assert_raise RuntimeError, "No input received for prompt", fn ->
      prompt("Enter something:")
    end
  end

  test "flush/1 removes all messages from inbox" do
    info("Test message")
    flush()
    refute_received {:ecto_backup_shell, _, _}
  end

  test "flush/1 with callback invokes callback for each message" do
    info("Message 1")
    warning("Message 2")
    flush(fn msg -> send(self(), {:flush_test, msg}) end)
    assert_received {:flush_test, {:ecto_backup_shell, :info, "Message 1"}}
    assert_received {:flush_test, {:ecto_backup_shell, :warning, "Message 2"}}
  end

  test "cmd/2 executes command and captures output" do
    {output, 0} = cmd("echo 'Hello World'")
    assert output == "Hello World\n"
    assert_received {:ecto_backup_shell, :cmd, "Hello World\n"}
  end
end
