defmodule Mix.Tasks.EctoBackup.Gen.ReleaseTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  import Bitwise

  setup do
    # Use a temporary directory for testing
    Temp.track!()
    test_dir = Temp.mkdir!(prefix: "ecto_backup_gen_release_test_")

    # Store original working directory and change to test directory
    original_dir = File.cwd!()
    File.cd!(test_dir)

    on_exit(fn ->
      File.cd!(original_dir)
    end)

    {:ok, test_dir: test_dir}
  end

  describe "run/1" do
    test "generates backup and restore scripts with default options", %{test_dir: test_dir} do
      output =
        capture_io(fn ->
          Mix.Tasks.EctoBackup.Gen.Release.run([])
        end)

      # Check that the output indicates files were created
      assert output =~ "* creating"
      assert output =~ "rel/overlays/bin/backup"
      assert output =~ "rel/overlays/bin/restore"

      # Check that the files exist
      backup_path = Path.join(test_dir, "rel/overlays/bin/backup")
      restore_path = Path.join(test_dir, "rel/overlays/bin/restore")
      assert File.exists?(backup_path)
      assert File.exists?(restore_path)

      # Check that files are executable
      backup_stat = File.stat!(backup_path)
      restore_stat = File.stat!(restore_path)
      assert backup_stat.mode |> band(0o111) != 0
      assert restore_stat.mode |> band(0o111) != 0
    end

    test "generates scripts with correct content for default app", %{test_dir: test_dir} do
      capture_io(fn ->
        Mix.Tasks.EctoBackup.Gen.Release.run([])
      end)

      app_name = Mix.Project.config() |> Keyword.fetch!(:app)

      backup_content = File.read!(Path.join(test_dir, "rel/overlays/bin/backup"))
      assert backup_content =~ "./#{app_name} eval \"EctoBackup.Release.backup(\\\"$*\\\")\""

      restore_content = File.read!(Path.join(test_dir, "rel/overlays/bin/restore"))
      assert restore_content =~ "./#{app_name} eval \"EctoBackup.Release.restore(\\\"$*\\\")\""
    end

    test "generates scripts with custom release name", %{test_dir: test_dir} do
      capture_io(fn ->
        Mix.Tasks.EctoBackup.Gen.Release.run(["--release", "my_custom_app"])
      end)

      backup_content = File.read!(Path.join(test_dir, "rel/overlays/bin/backup"))
      assert backup_content =~ "./my_custom_app eval \"EctoBackup.Release.backup(\\\"$*\\\")\""

      restore_content = File.read!(Path.join(test_dir, "rel/overlays/bin/restore"))
      assert restore_content =~ "./my_custom_app eval \"EctoBackup.Release.restore(\\\"$*\\\")\""
    end

    test "generates scripts in custom overlay directory", %{test_dir: test_dir} do
      output =
        capture_io(fn ->
          Mix.Tasks.EctoBackup.Gen.Release.run(["--overlay", "custom/overlay"])
        end)

      assert output =~ "custom/overlay/bin/backup"
      assert output =~ "custom/overlay/bin/restore"

      backup_path = Path.join(test_dir, "custom/overlay/bin/backup")
      restore_path = Path.join(test_dir, "custom/overlay/bin/restore")
      assert File.exists?(backup_path)
      assert File.exists?(restore_path)
    end

    test "generates scripts with both custom release and overlay options", %{test_dir: test_dir} do
      output =
        capture_io(fn ->
          Mix.Tasks.EctoBackup.Gen.Release.run([
            "--release",
            "custom_release",
            "--overlay",
            "my_overlay"
          ])
        end)

      assert output =~ "my_overlay/bin/backup"
      assert output =~ "my_overlay/bin/restore"

      backup_content = File.read!(Path.join(test_dir, "my_overlay/bin/backup"))
      assert backup_content =~ "./custom_release eval \"EctoBackup.Release.backup(\\\"$*\\\")\""

      restore_content = File.read!(Path.join(test_dir, "my_overlay/bin/restore"))
      assert restore_content =~ "./custom_release eval \"EctoBackup.Release.restore(\\\"$*\\\")\""
    end
  end
end
