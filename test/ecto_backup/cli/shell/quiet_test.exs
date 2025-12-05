defmodule EctoBackup.CLI.Shell.QuietTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias EctoBackup.CLI.Shell.Quiet, as: ShellQuiet

  setup do
    # Ensure ANSI disabled for predictable output
    ansi_enabled = Application.fetch_env!(:elixir, :ansi_enabled)
    Application.put_env(:elixir, :ansi_enabled, false)
    on_exit(fn -> Application.put_env(:elixir, :ansi_enabled, ansi_enabled) end)
    :ok
  end

  test "info/1 not output to stdout" do
    assert capture_io(fn -> ShellQuiet.info("This is an info message") end) == ""
  end

  test "warning/1 outputs to stdout" do
    output = capture_io(fn -> ShellQuiet.warning("This is a warning message") end)
    assert output == "This is a warning message\n"
  end

  test "error/1 outputs to stderr" do
    stderr_output = capture_io(:stderr, fn -> ShellQuiet.error("This is an error message") end)
    assert stderr_output == "This is an error message\n"
  end

  test "status/1 does not output anything" do
    assert capture_io(fn -> ShellQuiet.status("Current status") end) == ""
    assert capture_io(fn -> ShellQuiet.status(nil) end) == ""
  end

  test "prompt/1 outputs prompt and returns user input" do
    output =
      capture_io("user input", fn ->
        input = ShellQuiet.prompt("Enter something:")
        IO.write(input)
      end)

    assert output == "Enter something: user input"
  end

  test "cmd/2 captures output without emitting to stdout" do
    output =
      capture_io(fn ->
        assert {"Line1\nLine2\nLine3\n", 0} ==
                 ShellQuiet.cmd("echo 'Line1';echo 'Line2' >&2;echo 'Line3'")
      end)

    assert output == ""
  end
end
