defmodule EctoBackup.UtilTest do
  use ExUnit.Case, async: true
  use Patch
  alias EctoBackup.Util

  describe "cmd/2" do
    test "executes command and captures output" do
      {output, 0} = Util.cmd("echo 'Hello'\necho 'World'")
      assert output == "Hello\nWorld\n"
    end

    test "executes command with custom into" do
      {output, 0} = Util.cmd("echo 'Hello'\nsleep 0.1\necho 'World'", into: [])
      assert output == ["Hello\n", "World\n"]
      {output, 0} = Util.cmd("echo 'Hello'\necho 'World'", into: [], lines: 1024)
      assert output == ["Hello", "World"]

      assert_raise(ArgumentError, fn ->
        Util.cmd("echo 'Hello World'", into: nil)
      end)

      on_output = fn data ->
        send(self(), {:cmd_output, data})
      end

      {output, 0} = Util.cmd("echo 'Hello\nWorld'", on_output: on_output, into: [], lines: 1024)
      assert_received {:cmd_output, "Hello"}
      assert_received {:cmd_output, "World"}
      assert output == ["Hello", "World"]

      on_output = fn acc, data ->
        send(self(), {:cmd_output, data})
        [data | acc]
      end

      {output, 0} =
        Util.cmd("echo 'Hello\nWorld'", on_output: {[], on_output}, into: [], lines: 1024)

      assert_received {:cmd_output, "Hello"}
      assert_received {:cmd_output, "World"}
      assert output == ["Hello", "World"]
    end

    test "executes command with on_output callback" do
      on_output = fn data ->
        send(self(), {:cmd_output, data})
      end

      {output, 0} = Util.cmd("echo 'Hello'\nsleep 0.1\necho 'World'", on_output: on_output)
      assert_received {:cmd_output, "Hello\n"}
      assert_received {:cmd_output, "World\n"}
      assert output == "Hello\nWorld\n"

      {output, 0} = Util.cmd("echo 'Hello World'", on_output: on_output, into: nil)
      assert_received {:cmd_output, "Hello World\n"}
      assert output == nil

      on_output = fn acc, data ->
        send(self(), {:cmd_output, data})
        [data | acc]
      end

      {output, 0} = Util.cmd("echo 'Hello World'", on_output: {[], on_output}, into: nil)
      assert_received {:cmd_output, "Hello World\n"}
      assert output == nil
    end

    test "executes command that fails" do
      {output, exit_status} = Util.cmd({"sh", ["invalid_file"]})
      assert exit_status != 0
      assert output =~ "invalid_file: No such file or directory"
    end

    test "overrides on_output callback if quiet option is set" do
      on_output = fn data ->
        send(self(), {:cmd_output, data})
      end

      {output, 0} =
        Util.cmd("echo 'Hello'\necho 'World'", on_output: on_output, quiet: true)

      refute_received {:cmd_output, _}
      assert output == "Hello\nWorld\n"
    end
  end

  describe "timestamp/0" do
    test "returns current timestamp in HH:MM:SS.mmm format" do
      timestamp = Util.timestamp()
      assert Regex.match?(~r/^\d{2}:\d{2}:\d{2}\.\d{3}$/, timestamp)
    end
  end

  describe "duration/1" do
    test "formats from native time" do
      duration = System.convert_time_unit(512, :millisecond, :native)
      assert Util.duration(duration) == "512ms"

      duration = System.convert_time_unit(1534, :millisecond, :native)
      assert Util.duration(duration) == "1.53s"

      duration = System.convert_time_unit(65_478, :millisecond, :native)
      assert Util.duration(duration) == "1m 5.48s"

      duration = System.convert_time_unit(3_660_250, :millisecond, :native)
      assert Util.duration(duration) == "1h 1m 0.25s"
    end

    test "formats duration in milliseconds to human-readable string" do
      assert Util.duration(500, :millisecond) == "500ms"
      assert Util.duration(1500, :millisecond) == "1.5s"
      assert Util.duration(65_000, :millisecond) == "1m 5.0s"
      assert Util.duration(65_100, :millisecond) == "1m 5.1s"
      assert Util.duration(65_150, :millisecond) == "1m 5.15s"
      assert Util.duration(3_600_000, :millisecond) == "1h 0m 0.0s"
      assert Util.duration(3_600_150, :millisecond) == "1h 0m 0.15s"
      assert Util.duration(3_660_500, :millisecond) == "1h 1m 0.5s"
    end
  end
end
