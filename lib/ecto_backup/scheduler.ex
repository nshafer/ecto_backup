defmodule EctoBackup.Scheduler do
  @moduledoc """
  EctoBackup Scheduler to perform automatic backups of Ecto repositories based on cron schedules.

  This can be added to your supervision tree with:

      children = [
        EctoBackup.Scheduler,
      ]

      Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)

  All options of `EctoBackup.backup/1` can be provided here as well as a few extra options covered
  below.

      children = [
        {EctoBackup.Scheduler,
         repos: [
           MyApp.Repo,
           {MyApp.AnotherRepo, backup_dir: "/custom/backup/dir"}
         ],
         backup_schedule: "0 2 * * *",
         backup_stagger_sec: 300,
         backup_node: :node1@myhost},
      ]

  Options can also be provided in the application config or repo config and will be merged with
  those provided when starting the scheduler. Options provided when starting the scheduler take
  precedence over those in the config.

      # Backup all repos every day at 2am unless overridden in repo config
      config, :ecto_backup, backup_schedule: "0 2 * * *"

      # Backup this repo every 6 hours except sunday and monday
      config :ecto_backup, MyApp.Repo,
        backup_schedule: "0 */6 * * TUE-SAT",
        backup_stagger_sec: 600,
        backup_node: :primary@host

      # Never backup this repo automatically
      config :ecto_backup, MyApp.AnotherRepo,
        backup_schedule: nil

  ## Options

  - `:backup_schedule` - (string | `Crontab.CronExpression` | `{:extended, string}` | `nil`)
    A cron expression string or `Crontab.CronExpression` struct defining the backup schedule. If
    `nil`, automatic backups are disabled for the repo. Extended cron expressions can be provided
    with the `{:extended, string}` tuple. See [The Cron Notation
    Cheatsheet](`e:crontab:cron_notation.html`) for details on supported formats. Default is
    `nil`.
  - `:backup_stagger_sec` - (non-negative integer) Maximum number of seconds to randomly stagger
    the backup time to avoid all backups running at the same time. Default is `0`.
  - `:backup_node` - (atom | list(atom) | `nil`) Node or list of nodes on which to perform
    the backup. If the current node is not in the list, the backup will be skipped. If `nil`,
    backups can be performed on any node. Default is `nil`.

  ## Backups in a cluster

  Special consideration should be given when running in a distributed cluster. By adding
  `EctoBackup.Scheduler` to your supervision tree, if no other steps are taken, all nodes will
  attempt to perform backups for all repos according to their schedules. This can lead to multiple
  nodes trying to backup the same repo at the same time, possibly to the same file if using a
  shared filesystem, which can cause conflicts and data corruption.

  There are a few strategies to handle backups in a distributed cluster.

  ### Single node responsible for backups

  You can configure `:backup_node` either globally or per-repo to designate a single node to
  handle all backups. This ensures that only one node performs backups. For example:

      config, :ecto_backup,
        backup_node: :backup_node@myhost

      config :ecto_backup, MyApp.Repo,
        backup_node: :backup_node@myhost

  Downsides are that this requires you to know the name of the node ahead of time, and if that
  node goes down, backups will not be performed until it comes back up.

  ### Coordinating a backup node with external tool

  You can use an external tool to limit the `EctoBackup.Scheduler` to run only on a single node in
  the cluster. For example, using [Highlander](`e:highlander:Highlander`) or
  [HighlanderPG](`e:highlander_pg:HighlanderPG`) to ensure only one instance of a specific process
  is running in the cluster. This allows you to have failover for the backup process, but requires
  additional setup and configuration.

  Example using `Highlander`:

      children = [
        {Highlander, EctoBackup.Scheduler},
      ]

  """

  use Supervisor
  require Logger
  alias Crontab.CronExpression
  alias EctoBackup.Conf
  alias EctoBackup.ConfError
  alias EctoBackup.Util

  def start_link(opts) do
    options = Map.new(opts)

    with(
      {:ok, repo_specs} <- Util.get_repo_specs(:backup, options),
      {:ok, repo_configs} <- Util.get_repo_configs(:backup, repo_specs),
      {:ok, repo_schedules} <- get_repo_schedules(repo_configs, options)
    ) do
      Supervisor.start_link(__MODULE__, {repo_schedules, options}, name: __MODULE__)
    else
      {:error, reason} ->
        Logger.error("EctoBackup.Scheduler failed to start: #{Exception.message(reason)}")
        :ignore
    end
  end

  def init({repo_schedules, options}) do
    children = [
      {EctoBackup.Scheduler.Manager, {repo_schedules, options}},
      {Task.Supervisor, name: EctoBackup.Scheduler.TaskSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc """
  Returns a map of the time remaining in milliseconds until the next scheduled backup for each
  repo.
  """
  def timers() do
    GenServer.call(EctoBackup.Scheduler.Manager, :get_timers)
  end

  @doc """
  Returns a map of the next scheduled backup `DateTime` for each repo.
  """
  def schedule() do
    GenServer.call(EctoBackup.Scheduler.Manager, :get_schedule)
  end

  @doc """
  Returns a map of repos currently performing backups and a `DateTime` of when they started.
  """
  def backups_in_progress() do
    GenServer.call(EctoBackup.Scheduler.Manager, :get_backups_in_progress)
  end

  @doc """
  Immediately starts a backup for the given `repo`.

  Returns `:ok` if the backup was started, or `{:error, :backup_already_in_progress}` if a backup
  is already running for the given `repo`.
  """
  def backup_now(repo) do
    GenServer.call(EctoBackup.Scheduler.Manager, {:backup_now, repo})
  end

  defp get_repo_schedules(repo_configs, options) do
    schedules =
      for {repo, repo_config} <- repo_configs, into: %{} do
        {repo,
         %{
           cron_expression: get_repo_schedule!(repo, repo_config, options),
           stagger_sec: get_repo_stagger_sec!(repo, repo_config, options),
           nodes: get_repo_backup_nodes!(repo, repo_config, options)
         }}
      end

    {:ok, schedules}
  rescue
    e in ConfError ->
      {:error, e}
  end

  defp get_repo_schedule!(repo, repo_config, options) do
    case Conf.fetch(repo_config, options, :backup_schedule) do
      {:ok, value} -> parse_backup_schedule(repo, value)
      :error -> nil
    end
  end

  defp parse_backup_schedule(_repo, nil), do: nil
  defp parse_backup_schedule(_repo, %CronExpression{} = cron_expression), do: cron_expression

  defp parse_backup_schedule(_repo, {:extended, schedule}) when is_binary(schedule) do
    case CronExpression.Parser.parse(schedule, true) do
      {:ok, cron_expression} ->
        cron_expression

      {:error, reason} ->
        raise ConfError,
          reason: :invalid_cron_schedule,
          message: "Invalid cron schedule: #{inspect(reason)}"
    end
  end

  defp parse_backup_schedule(_repo, schedule) when is_binary(schedule) do
    case CronExpression.Parser.parse(schedule) do
      {:ok, cron_expression} ->
        cron_expression

      {:error, reason} ->
        raise ConfError,
          reason: :invalid_cron_schedule,
          message: "Invalid cron schedule: #{inspect(reason)}"
    end
  end

  defp parse_backup_schedule(repo, invalid) do
    raise ConfError, reason: :invalid_backup_schedule, repo: repo, value: invalid
  end

  defp get_repo_stagger_sec!(repo, repo_config, options) do
    case Conf.fetch(repo_config, options, :backup_stagger_sec) do
      {:ok, stagger_sec} when is_integer(stagger_sec) and stagger_sec >= 0 ->
        stagger_sec

      {:ok, invalid} ->
        raise ConfError, reason: :invalid_backup_stagger_sec, repo: repo, value: invalid

      :error ->
        0
    end
  end

  defp get_repo_backup_nodes!(repo, repo_config, options) do
    case Conf.fetch(repo_config, options, :backup_node) do
      {:ok, node} when is_atom(node) or is_nil(node) ->
        [node]

      {:ok, nodes} when is_list(nodes) ->
        if Enum.all?(nodes, &is_atom/1) do
          nodes
        else
          raise ConfError, reason: :invalid_backup_node, repo: repo, value: nodes
        end

      {:ok, invalid} ->
        raise ConfError, reason: :invalid_backup_node, repo: repo, value: invalid

      :error ->
        nil
    end
  end
end
