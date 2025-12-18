defmodule EctoBackup.SchedulerTest do
  use ExUnit.Case
  use Patch
  import ExUnit.CaptureLog
  import Crontab.CronExpression
  alias EctoBackup.Scheduler

  defp await_scheduled_backups(repos, elapsed \\ 0, timeout \\ 1000) do
    schedule = Scheduler.schedule()

    if Enum.all?(repos, fn repo -> Map.has_key?(schedule, repo) end) do
      :ok
    else
      if elapsed >= timeout do
        missing = Enum.filter(repos, fn repo -> not Map.has_key?(schedule, repo) end)
        flunk("Timed out waiting for backups to be scheduled for #{inspect(missing)}")
      else
        Process.sleep(10)
        await_scheduled_backups(repos, elapsed + 10, timeout)
      end
    end
  end

  setup_all do
    old_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: old_level) end)
  end

  describe "start_link/1 configuration parsing" do
    setup do
      patch(Supervisor, :start_link, fn _, _, _ -> {:ok, :patched} end)
      :ok
    end

    test "starts with valid options" do
      opts = %{repos: [{EctoBackup.TestRepo, adapter: EctoBackup.StubAdapter}]}
      assert {:ok, :patched} = Scheduler.start_link(opts)

      opts = Map.put(opts, :backup_schedule, nil)
      assert {:ok, :patched} = Scheduler.start_link(opts)

      opts = Map.put(opts, :backup_schedule, "0 2 * * *")
      assert {:ok, :patched} = Scheduler.start_link(opts)

      opts = Map.put(opts, :backup_schedule, {:extended, "0 */6 * * *"})
      assert {:ok, :patched} = Scheduler.start_link(opts)

      opts = Map.put(opts, :backup_schedule, ~e[0 2 * * *])
      assert {:ok, :patched} = Scheduler.start_link(opts)

      opts = Map.put(opts, :backup_stagger_sec, 300)
      assert {:ok, :patched} = Scheduler.start_link(opts)

      opts = Map.put(opts, :backup_node, :node1@localhost)
      assert {:ok, :patched} = Scheduler.start_link(opts)

      opts = Map.put(opts, :backup_node, [:node1@localhost, :node2@localhost])
      assert {:ok, :patched} = Scheduler.start_link(opts)
    end

    test "logs error and returns :ignore on invalid :backup_schedule" do
      opts = %{repos: [{EctoBackup.TestRepo, adapter: EctoBackup.StubAdapter}]}

      opts = Map.put(opts, :backup_schedule, "invalid cron")
      log = capture_log(fn -> assert :ignore == Scheduler.start_link(opts) end)
      assert log =~ "EctoBackup.Scheduler failed to start"

      opts = Map.put(opts, :backup_schedule, {:extended, "invalid cron"})
      log = capture_log(fn -> assert :ignore == Scheduler.start_link(opts) end)
      assert log =~ "EctoBackup.Scheduler failed to start"

      opts = Map.put(opts, :backup_schedule, 123)
      log = capture_log(fn -> assert :ignore == Scheduler.start_link(opts) end)
      assert log =~ "EctoBackup.Scheduler failed to start"
    end

    test "logs error and returns :ignore on invalid :backup_stagger_sec" do
      opts = %{
        repos: [{EctoBackup.TestRepo, adapter: EctoBackup.StubAdapter}],
        backup_schedule: "* * * * *"
      }

      opts = Map.put(opts, :backup_stagger_sec, -10)
      log = capture_log(fn -> assert :ignore == Scheduler.start_link(opts) end)
      assert log =~ "EctoBackup.Scheduler failed to start"

      opts = Map.put(opts, :backup_stagger_sec, "not_an_integer")
      log = capture_log(fn -> assert :ignore == Scheduler.start_link(opts) end)
      assert log =~ "EctoBackup.Scheduler failed to start"

      opts = Map.put(opts, :backup_stagger_sec, -10)
      opts = Map.put(opts, :backup_node, "not_an_atom")
      log = capture_log(fn -> assert :ignore == Scheduler.start_link(opts) end)
      assert log =~ "EctoBackup.Scheduler failed to start"
    end

    test "logs error and returns :ignore on invalid :backup_node" do
      opts = %{
        repos: [{EctoBackup.TestRepo, adapter: EctoBackup.StubAdapter}],
        backup_schedule: "* * * * *"
      }

      opts = Map.put(opts, :backup_node, "not_an_atom")
      log = capture_log(fn -> assert :ignore == Scheduler.start_link(opts) end)
      assert log =~ "EctoBackup.Scheduler failed to start"

      opts = Map.put(opts, :backup_node, [:node1@localhost, "not_an_atom"])
      log = capture_log(fn -> assert :ignore == Scheduler.start_link(opts) end)
      assert log =~ "EctoBackup.Scheduler failed to start"
    end
  end

  describe "start_link/1" do
    test "starts the scheduler supervision tree" do
      log =
        capture_log(fn ->
          opts = %{repos: [{EctoBackup.TestRepo, adapter: EctoBackup.StubAdapter}]}
          start_supervised!({Scheduler, opts})
          pid = Process.whereis(EctoBackup.Scheduler)
          assert Process.alive?(pid)

          manager_pid = Process.whereis(EctoBackup.Scheduler.Manager)
          assert is_pid(manager_pid)
          assert Process.alive?(manager_pid)

          task_supervisor_pid = Process.whereis(EctoBackup.Scheduler.TaskSupervisor)
          assert is_pid(task_supervisor_pid)
          assert Process.alive?(task_supervisor_pid)
        end)

      assert log == ""
    end

    test "schedules a backup for each repo" do
      year = DateTime.utc_now().year

      log =
        capture_log(fn ->
          opts = %{
            repos: [
              {EctoBackup.TestRepo, adapter: EctoBackup.StubAdapter},
              {EctoBackup.SecondTestRepo,
               adapter: EctoBackup.StubAdapter, backup_stagger_sec: 86400}
            ],
            backup_schedule: "* * * * * #{year + 1}"
          }

          start_supervised!({Scheduler, opts})
          await_scheduled_backups([EctoBackup.TestRepo, EctoBackup.SecondTestRepo])
        end)

      assert log =~ "Next backup for EctoBackup.TestRepo scheduled at #{year + 1}-"
      assert %{EctoBackup.TestRepo => _date} = Scheduler.schedule()
      assert %{EctoBackup.TestRepo => _ms} = Scheduler.timers()
      assert Scheduler.backups_in_progress() == %{}

      assert log =~ "Next backup for EctoBackup.SecondTestRepo scheduled at #{year + 1}-"
      assert %{EctoBackup.SecondTestRepo => date} = Scheduler.schedule()
      assert date.second != 0 or date.minute != 0 or date.hour != 0
      assert %{EctoBackup.SecondTestRepo => _ms} = Scheduler.timers()
      assert Scheduler.backups_in_progress() == %{}
    end

    test "performs backup when backup_now/1 is called" do
      backup_dir = EctoBackup.StubAdapter.create_backup_dir!()

      # Attach telemetry handler to wait for backup completion
      test_pid = self()

      fun = fn _, _, %{repo: repo, result: result}, _ ->
        send(test_pid, {:backup_completed, repo, result})
      end

      capture_log(fn ->
        :telemetry.attach("test-complete", [:ecto_backup, :backup, :repo, :stop], fun, nil)
      end)

      on_exit(fn -> :telemetry.detach("test-complete") end)

      log =
        capture_log(fn ->
          opts = %{
            repos: [{EctoBackup.TestRepo, adapter: EctoBackup.StubAdapter}],
            backup_dir: backup_dir
          }

          start_supervised!({Scheduler, opts})
          assert :ok = Scheduler.backup_now(EctoBackup.TestRepo)

          # Try to start second backup while first is running
          assert {:error, :backup_already_in_progress} = Scheduler.backup_now(EctoBackup.TestRepo)

          # Wait for backup to complete
          assert_receive {:backup_completed, EctoBackup.TestRepo,
                          {:ok, EctoBackup.TestRepo, backup_file}},
                         2000

          assert File.exists?(backup_file)
          assert Scheduler.backups_in_progress() == %{}
        end)

      assert log =~ "Starting backup of EctoBackup.TestRepo"
      assert log =~ "Backup of EctoBackup.TestRepo completed"
    end

    test "handles backup failure" do
      backup_dir = EctoBackup.StubAdapter.create_backup_dir!()
      test_pid = self()

      fun = fn _, _, %{repo: repo, result: result}, _ ->
        send(test_pid, {:backup_completed, repo, result})
      end

      capture_log(fn ->
        :telemetry.attach("test-backup-fail", [:ecto_backup, :backup, :repo, :stop], fun, nil)
      end)

      on_exit(fn -> :telemetry.detach("test-backup-fail") end)

      capture_log(fn ->
        opts = %{
          repos: [{EctoBackup.TestRepo, adapter: EctoBackup.StubAdapter}],
          backup_dir: backup_dir,
          backup_file: "invalid_backup_file.db"
        }

        start_supervised!({Scheduler, opts})
        assert :ok = Scheduler.backup_now(EctoBackup.TestRepo)

        # Wait for backup to complete with error
        assert_receive {:backup_completed, EctoBackup.TestRepo,
                        {:error, EctoBackup.TestRepo, reason}},
                       2000

        # Verify the error reason
        assert reason.reason == :invalid_backup_file
        assert Scheduler.backups_in_progress() == %{}
      end)
    end

    test "handles backup task returning error" do
      backup_dir = EctoBackup.StubAdapter.create_backup_dir!()

      old_level = Logger.level()
      Logger.configure(level: :error)

      log =
        capture_log(fn ->
          # Use a backup_file callback that returns invalid value
          invalid_backup_file_fn = fn _repo, _config -> :invalid end

          opts = %{
            repos: [{EctoBackup.TestRepo, adapter: EctoBackup.StubAdapter}],
            backup_dir: backup_dir,
            backup_file: invalid_backup_file_fn
          }

          start_supervised!({Scheduler, opts})
          assert :ok = Scheduler.backup_now(EctoBackup.TestRepo)

          # Wait for the task to complete
          Process.sleep(100)

          # Verify the backup is no longer in progress
          assert Scheduler.backups_in_progress() == %{}
        end)

      Logger.configure(level: old_level)

      assert log =~ "Backup of EctoBackup.TestRepo task failed"
      assert log =~ "invalid backup file path"
    end

    test "skips scheduling backup when node is not in allowed nodes" do
      old_level = Logger.level()
      Logger.configure(level: :debug)

      log =
        capture_log(fn ->
          opts = %{
            repos: [{EctoBackup.TestRepo, adapter: EctoBackup.StubAdapter}],
            backup_schedule: "* * * * *",
            backup_node: :some_other_node@localhost
          }

          start_supervised!({Scheduler, opts})
          Process.sleep(50)
        end)

      Logger.configure(level: old_level)

      # Should not schedule backup because current node is not in allowed nodes
      assert log =~ "Node not in backup_nodes for EctoBackup.TestRepo"
      assert Scheduler.schedule() == %{}
    end

    test "handles backup task crash" do
      old_level = Logger.level()
      Logger.configure(level: :error)

      log =
        capture_log(fn ->
          # Use a backup_dir function that raises to trigger a crash
          crash_fn = fn _repo, _config ->
            raise "Intentional crash for testing"
          end

          opts = %{
            repos: [{EctoBackup.TestRepo, adapter: EctoBackup.StubAdapter}],
            backup_dir: crash_fn
          }

          start_supervised!({Scheduler, opts})

          assert :ok = Scheduler.backup_now(EctoBackup.TestRepo)

          # Wait a bit for the task to crash and be handled
          Process.sleep(100)

          # Verify the backup is no longer in progress after crash
          assert Scheduler.backups_in_progress() == %{}
        end)

      Logger.configure(level: old_level)

      assert log =~ "Backup task for EctoBackup.TestRepo crashed"
      assert log =~ "Intentional crash for testing"
    end
  end
end
