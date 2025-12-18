defmodule EctoBackup.Scheduler.Manager do
  @moduledoc false

  use GenServer
  require Logger
  alias Crontab.CronExpression
  alias EctoBackup.Util

  def start_link(init_arg) do
    Logger.debug("[EctoBackup] Starting Scheduler Manager")
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init({repo_schedules, options}) do
    state = %{
      repo_schedules: repo_schedules,
      options: options,
      timers: %{},
      start_monotonic_times: %{},
      start_system_times: %{},
      repo_tasks: %{},
      task_repos: %{}
    }

    {:ok, state, {:continue, :schedule_next_backup}}
  end

  @impl true
  def handle_continue(:schedule_next_backup, state) do
    {:noreply, schedule_next_backups(state)}
  end

  @impl true
  def handle_call(:get_timers, _from, state) do
    timers =
      for {repo, timer} <- state.timers, into: %{} do
        {repo, Process.read_timer(timer)}
      end

    {:reply, timers, state}
  end

  def handle_call(:get_schedule, _from, state) do
    schedule =
      for {repo, timer} <- state.timers, into: %{} do
        now = DateTime.utc_now()
        timer = Process.read_timer(timer)
        {repo, DateTime.add(now, timer, :millisecond)}
      end

    {:reply, schedule, state}
  end

  def handle_call(:get_backups_in_progress, _from, state) do
    start_times =
      for {repo, start_time} <- state.start_system_times, into: %{} do
        {repo, DateTime.from_unix!(start_time, :native)}
      end

    {:reply, start_times, state}
  end

  def handle_call({:backup_now, repo}, _from, state) do
    if Map.has_key?(state.repo_tasks, repo) do
      {:reply, {:error, :backup_already_in_progress}, state}
    else
      send(self(), {:perform_backup, repo})
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info({:perform_backup, repo}, state) do
    {_, state} = pop_in(state.timers[repo])

    if Map.has_key?(state.repo_tasks, repo) do
      Logger.warning([
        "[EctoBackup] Backup for #{inspect(repo)} was scheduled to run but a backup ",
        "is already running! This scheduled backup will be skipped."
      ])

      {:noreply, state}
    else
      # If the user provided a list of repo specs in options, pull out the one for this repo,
      # otherwise we just use the repo as-is with no overrides and pass the rest of the options.
      repos = Map.get(state.options, :repos, [])
      repo_spec = Enum.find(repos, repo, fn {r, _} -> r == repo end)
      options = Map.put(state.options, :repos, [repo_spec])

      task =
        Task.Supervisor.async_nolink(EctoBackup.Scheduler.TaskSupervisor, fn ->
          Logger.info("[EctoBackup] Starting backup of #{inspect(repo)}")
          EctoBackup.backup(options)
        end)

      state = put_in(state.start_monotonic_times[repo], :erlang.monotonic_time())
      state = put_in(state.start_system_times[repo], :erlang.system_time())
      state = put_in(state.repo_tasks[repo], task)
      state = put_in(state.task_repos[task.ref], repo)

      {:noreply, state}
    end
  end

  @impl true
  # Handle completed backup task
  def handle_info({ref, result}, state) do
    Process.demonitor(ref, [:flush])

    {repo, state} = pop_in(state.task_repos[ref])
    {_, state} = pop_in(state.repo_tasks[repo])
    {_, state} = pop_in(state.start_system_times[repo])
    {start_time, state} = pop_in(state.start_monotonic_times[repo])
    elapsed = :erlang.monotonic_time() - start_time

    case result do
      {:ok, [{:ok, ^repo, backup_file}]} ->
        Logger.info([
          "[EctoBackup] Backup of #{inspect(repo)} completed ",
          "in #{Util.duration(elapsed)} to file #{backup_file}"
        ])

      {:ok, [{:error, ^repo, reason}]} ->
        Logger.error([
          "[EctoBackup] Backup of #{inspect(repo)} failed ",
          "after #{Util.duration(elapsed)}: ",
          Exception.message(reason)
        ])

      {:error, reason} ->
        Logger.error([
          "[EctoBackup] Backup of #{inspect(repo)} task failed: ",
          Exception.message(reason)
        ])

      other ->
        Logger.error([
          "[EctoBackup] Backup of #{inspect(repo)} returned unexpected result ",
          "after #{Util.duration(elapsed)}: #{inspect(other)}"
        ])
    end

    {:noreply, schedule_next_backup(repo, state.repo_schedules[repo], state)}
  end

  # Handle crashed backup task
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {repo, state} = pop_in(state.task_repos[ref])
    {_, state} = pop_in(state.repo_tasks[repo])
    {_, state} = pop_in(state.start_system_times[repo])
    {start_time, state} = pop_in(state.start_monotonic_times[repo])
    elapsed = :erlang.monotonic_time() - start_time

    case reason do
      {%name{} = exception, stacktrace} ->
        Logger.error([
          "[EctoBackup] Backup task for #{inspect(repo)} crashed ",
          "after #{Util.duration(elapsed)} ",
          "with exception #{inspect(name)}: #{Exception.message(exception)}\n",
          "Stacktrace:\n",
          Exception.format_stacktrace(stacktrace)
        ])

      {reason, stacktrace} ->
        Logger.error([
          "[EctoBackup] Backup task for #{inspect(repo)} crashed ",
          "after #{Util.duration(elapsed)} ",
          "with reason: #{inspect(reason)}\n",
          "Stacktrace:\n",
          Exception.format_stacktrace(stacktrace)
        ])

      %name{} = exception ->
        Logger.error([
          "[EctoBackup] Backup task for #{inspect(repo)} crashed ",
          "after #{Util.duration(elapsed)} ",
          "with exception #{inspect(name)}: #{Exception.message(exception)}"
        ])

      reason ->
        Logger.error([
          "[EctoBackup] Backup task for #{inspect(repo)} crashed ",
          "after #{Util.duration(elapsed)} ",
          "with reason: #{inspect(reason)}"
        ])
    end

    state = schedule_next_backup(repo, state.repo_schedules[repo], state)
    {:noreply, state}
  end

  defp schedule_next_backups(%{repo_schedules: repo_schedules} = state) do
    for {repo, repo_schedule} <- repo_schedules, reduce: state do
      state -> schedule_next_backup(repo, repo_schedule, state)
    end
  end

  defp schedule_next_backup(repo, repo_schedule, state) do
    %{cron_expression: cron_expression, stagger_sec: stagger_sec, nodes: nodes} = repo_schedule
    %{timers: timers, repo_tasks: repo_tasks} = state

    cond do
      cron_expression == nil ->
        Logger.debug("[EctoBackup] No backup schedule for #{inspect(repo)}, skipping.")
        state

      Map.has_key?(timers, repo) ->
        Logger.warning("[EctoBackup] Backup already scheduled for #{inspect(repo)}!")
        state

      Map.has_key?(repo_tasks, repo) ->
        Logger.warning("[EctoBackup] Backup task already running for #{inspect(repo)}!")
        state

      nodes != nil and Node.self() not in nodes ->
        Logger.debug("[EctoBackup] Node not in backup_nodes for #{inspect(repo)}, skipping.")
        state

      true ->
        {next_run, after_sec, delay_sec} = get_next_run(cron_expression, stagger_sec)

        Logger.info([
          "[EctoBackup] Next backup for #{inspect(repo)} scheduled at #{next_run} UTC",
          if(delay_sec > 0, do: " (including random stagger of #{delay_sec} seconds)", else: "")
        ])

        timer = Process.send_after(self(), {:perform_backup, repo}, after_sec * 1000)
        put_in(state.timers[repo], timer)
    end
  end

  defp get_next_run(%CronExpression{} = cron_expression, stagger_sec) do
    now = NaiveDateTime.utc_now()
    next_run = Crontab.Scheduler.get_next_run_date!(cron_expression, now)
    diff_sec = NaiveDateTime.diff(next_run, now, :second)
    random_stagger_sec = get_random_stagger(stagger_sec)
    next_run_with_delay = NaiveDateTime.add(next_run, random_stagger_sec, :second)
    {next_run_with_delay, diff_sec + random_stagger_sec, random_stagger_sec}
  end

  defp get_random_stagger(0), do: 0
  defp get_random_stagger(stagger_sec), do: :rand.uniform(stagger_sec)
end
