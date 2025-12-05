defmodule EctoBackup.CLI.Shell.IOTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  alias EctoBackup.CLI.Shell.IO, as: ShellIO
  alias EctoBackup.State

  setup_all do
    ansi_enabled = Application.fetch_env!(:elixir, :ansi_enabled)
    on_exit(fn -> Application.put_env(:elixir, :ansi_enabled, ansi_enabled) end)
    :ok
  end

  describe "ANSI disabled" do
    setup do
      # Ensure ANSI disabled for predictable output
      ansi_enabled = Application.fetch_env!(:elixir, :ansi_enabled)
      Application.put_env(:elixir, :ansi_enabled, false)
      on_exit(fn -> Application.put_env(:elixir, :ansi_enabled, ansi_enabled) end)
      :ok
    end

    test "info/1 prints message with newline without ANSI" do
      output = capture_io(fn -> assert :ok == ShellIO.info("Hello") end)
      assert output == "Hello\n"
    end

    test "warning/1 prints warning without ANSI" do
      output = capture_io(fn -> assert :ok == ShellIO.warning("Caution") end)
      assert output == "Caution\n"
    end

    test "error/1 prints error to stderr without ANSI" do
      stderr_output = capture_io(:stderr, fn -> assert :ok == ShellIO.error("Failure") end)
      assert stderr_output == "Failure\n"
    end

    test "status/1 does nothing when ANSI is disabled" do
      output = capture_io(fn -> assert :ok == ShellIO.status("Working") end)
      assert output == ""
      output = capture_io(fn -> assert :ok == ShellIO.status(nil) end)
      assert output == ""
    end

    test "status is not reprinted after info/warning/error when ANSI is disabled" do
      State.put(:current_status, "StatusLine")

      info_output = capture_io(fn -> assert :ok == ShellIO.info("InfoMessage") end)
      assert info_output == "InfoMessage\n"

      warning_output = capture_io(fn -> assert :ok == ShellIO.warning("WarnMessage") end)
      assert warning_output == "WarnMessage\n"

      error_output = capture_io(:stderr, fn -> assert :ok == ShellIO.error("ErrorMessage") end)
      assert error_output == "ErrorMessage\n"
    end

    test "prompt/1 displays prompt message and returns user input" do
      output =
        capture_io("user input", fn ->
          input = ShellIO.prompt("Enter something:")
          IO.write(input)
        end)

      assert output == "Enter something: user input"
    end

    test "raises if input is EOF" do
      assert_raise RuntimeError,
                   "EctoBackup.CLI.shell().prompt/1 received EOF",
                   fn ->
                     assert capture_io(fn ->
                              ShellIO.prompt("Enter something:")
                            end) == "Enter something: "
                   end
    end

    test "cmd/2 forwards command output without ANSI" do
      output =
        capture_io(fn ->
          assert {"Line1\nLine2\nLine3\n", 0} ==
                   ShellIO.cmd("echo 'Line1'\necho 'Line2' >&2\necho 'Line3'")
        end)

      assert output == "Line1\nLine2\nLine3\n"
    end

    test "cmd/2 does not output if quiet option is set" do
      output =
        capture_io(fn ->
          assert {"Line1\nLine2\n", 0} ==
                   ShellIO.cmd("echo 'Line1'\necho 'Line2'", quiet: true)
        end)

      assert output == ""
    end
  end

  defp atos(ansidata) do
    ansidata
    |> IO.ANSI.format_fragment(true)
    |> IO.chardata_to_string()
  end

  describe "ANSI enabled" do
    setup do
      # Ensure ANSI enabled for predictable output
      ansi_enabled = Application.fetch_env!(:elixir, :ansi_enabled)
      Application.put_env(:elixir, :ansi_enabled, true)
      on_exit(fn -> Application.put_env(:elixir, :ansi_enabled, ansi_enabled) end)

      # Ensure no prior status
      State.delete(:current_status)
      on_exit(fn -> State.delete(:current_status) end)
      :ok
    end

    test "info/1 prints message with newline after clearing line" do
      output = capture_io(fn -> assert :ok == ShellIO.info([:bright, "Hello"]) end)
      assert output == atos(["\r", :clear_line, :bright, "Hello", :reset, "\n"])
    end

    test "warning/1 prints bright yellow message after clearing line" do
      output = capture_io(fn -> assert :ok == ShellIO.warning(["Caution"]) end)
      assert output == atos(["\r", :clear_line, :yellow, "Caution", :reset, "\n"])
    end

    test "error/1 prints bright red message to stderr after clearing line" do
      stderr_output = capture_io(:stderr, fn -> assert :ok == ShellIO.error(["Failure"]) end)
      assert stderr_output == atos(["\r", :clear_line, :red, "Failure", :reset, "\n"])
    end

    test "status/1 sets current_status and writes without newline" do
      output = capture_io(fn -> assert :ok == ShellIO.status([:bright, "Working"]) end)
      assert output == atos(["\r", :clear_line, :bright, "Working", :reset])
      assert State.get(:current_status) == [:bright, "Working"]
    end

    test "status(nil) clears the current line" do
      output = capture_io(fn -> assert :ok == ShellIO.status([:bright, "Working"]) end)
      assert output == atos(["\r", :clear_line, :bright, "Working", :reset])
      assert State.get(:current_status) == [:bright, "Working"]
      output = capture_io(fn -> assert :ok == ShellIO.status(nil) end)
      # Clearing prints carriage return + clear line escape; message itself should be empty
      assert output == atos(["\r", :clear_line, :reset])
      assert State.fetch(:current_status) == :error
    end

    test "info/1 prints message with newline and reprints current status" do
      # Set status without writing to IO
      State.put(:current_status, [:bright, "Hold"])
      output = capture_io(fn -> assert :ok == ShellIO.info([:bright, "Hello"]) end)

      assert output ==
               atos(["\r", :clear_line, :bright, "Hello", :reset, "\n"]) <>
                 atos(["\r", :clear_line, :bright, "Hold", :reset])
    end

    test "warning/1 prints yellow bright message and reprints status" do
      State.put(:current_status, [:bright, "Stay"])
      output = capture_io(fn -> assert :ok == ShellIO.warning(["Caution"]) end)

      assert output ==
               atos(["\r", :clear_line, :yellow, "Caution", :reset, "\n"]) <>
                 atos(["\r", :clear_line, :bright, "Stay", :reset])
    end

    test "error/1 prints to stderr and reprints status on stdout" do
      State.put(:current_status, [:bright, "AfterError"])

      output =
        capture_io(fn ->
          # Capture stderr separately to inspect error output
          err_output = capture_io(:stderr, fn -> assert :ok == ShellIO.error(["Failure"]) end)
          assert err_output == atos(["\r", :clear_line, :red, "Failure", :reset, "\n"])
        end)

      assert output == atos(["\r", :clear_line, :bright, "AfterError", :reset])
    end

    test "cmd/2 prints output with a status line" do
      output = capture_io(fn -> assert :ok == ShellIO.status([:bright, "Working"]) end)
      assert output == atos(["\r", :clear_line, :bright, "Working", :reset])

      output =
        capture_io(fn ->
          assert {"Line1\nLine2\nLine3\n", 0} ==
                   ShellIO.cmd(
                     "echo 'Line1'; sleep 0.1;" <>
                       "echo -n 'Line'; sleep 0.1; echo '2'; sleep 0.1;" <>
                       "echo 'Line3'"
                   )
        end)

      assert output ==
               atos([
                 ["\r", :clear_line, "Line1\n"],
                 ["\r", :clear_line, :bright, "Working", :reset],
                 ["\r", :clear_line, "Line", "2\n"],
                 ["\r", :clear_line, :bright, "Working", :reset],
                 ["\r", :clear_line, "Line3\n"],
                 ["\r", :clear_line, :bright, "Working", :reset]
               ])
    end
  end
end
