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
end
