defmodule EctoBackup.ConfError do
  @moduledoc """
  Exception module for EctoBackup configuration errors.
  """
  require Logger

  defexception [:reason, :repo, :value, :message]

  @type t :: %__MODULE__{
          reason: atom(),
          repo: Ecto.Repo.t() | nil,
          value: term() | nil,
          message: String.t() | nil
        }

  @impl true
  def exception(opts) do
    reason = Keyword.fetch!(opts, :reason)
    value = Keyword.get(opts, :value)
    repo = Keyword.get(opts, :repo)
    message = Keyword.get(opts, :message)

    %__MODULE__{
      reason: reason,
      value: value,
      repo: repo,
      message: message || message_for(reason, %{repo: repo, value: value})
    }
  end

  defp message_for(:invalid_repo_list, %{value: repo_list}) do
    """
    invalid :repos configuration, expected a list of repo modules or {module, config} tuples

    Got value:

        #{inspect(repo_list)}
    """
  end

  defp message_for(:no_default_repos, _opts) do
    """
    no default repositories found, please configure :repos in the :ecto_backup application config

    Examples:

        # In app config
        config :ecto_backup, repos: [MyApp.Repo]

        # When running the mix task
        mix ecto_backup.backup -r MyApp.Repo

        # When running the release task
        ./backup --repo MyApp.Repo
    """
  end

  defp message_for(:invalid_repo_spec, %{value: repo_spec}) do
    "invalid repo specification, expected atom or {module, keyword}, got: #{inspect(repo_spec)}"
  end

  defp message_for(:invalid_repo_config, %{repo: repo, value: config}) do
    "invalid repo config returned from #{inspect(repo)}.config/0, got: #{inspect(config)}"
  end

  defp message_for(:invalid_repo, %{repo: repo}) do
    "#{inspect(repo)} is not a valid Ecto.Repo module"
  end

  defp message_for(:invalid_backup_file, %{repo: repo, value: invalid}) do
    "invalid :backup_file for #{inspect(repo)}, expected a string, got #{inspect(invalid)}"
  end

  defp message_for(:invalid_restore_file, %{repo: repo, value: invalid}) do
    "invalid :restore_file for #{inspect(repo)}, expected a string, got #{inspect(invalid)}"
  end

  defp message_for(:invalid_backup_dir, %{value: invalid}) do
    "invalid backup directory path, expected a string, got #{inspect(invalid)}"
  end

  defp message_for(:invalid_restore_dir, %{value: invalid}) do
    "invalid restore directory path, expected a string, got #{inspect(invalid)}"
  end

  defp message_for(:no_backup_dir_set, %{repo: repo}) do
    "no backup directory is set for repo #{inspect(repo)}, so a backup file cannot be " <>
      "generated, please set the :backup_dir option or specify a :backup_file in the " <>
      "repo configuration\n\n" <>
      """
      Examples:

        # In app config
        config :ecto_backup, backup_dir: "/path/to/backup/dir"

        # When running the mix task
        mix ecto_backup.backup -d /path/to/backup/dir

        # When running the release task
        ./backup --backup-dir /path/to/backup/dir
      """
  end

  defp message_for(:no_restore_dir_set, %{repo: repo}) do
    "no restore directory is set for repo #{inspect(repo)}, so a restore file cannot be " <>
      "located, please set the :restore_dir option or specify a :restore_file in the " <>
      "repo configuration\n\n" <>
      """
      Examples:

          # In app config
          config :ecto_backup, restore_dir: "/path/to/restore/dir"

          # When running the mix task
          mix ecto_backup.restore -d /path/to/restore/dir

          # When running the release task
          ./restore --restore-dir /path/to/restore/dir
      """
  end

  defp message_for(:no_repos_to_backup, _opts) do
    "no repositories to back up, please provide at least one repository in the :repos option " <>
      "or configure :repos in the :ecto_backup application config\n\n" <>
      """
      Examples:

          # In app config
          config :ecto_backup, repos: [MyApp.Repo]

          # When running the mix task
          mix ecto_backup.backup -r MyApp.Repo

          # When running the release task
          ./backup --repo MyApp.Repo
      """
  end

  defp message_for(:no_repos_to_restore, _opts) do
    "no repositories to restore, please provide at least one repository in the :repos option " <>
      "or configure :repos in the :ecto_backup application config\n\n" <>
      """
      Examples:

          # In app config
          config :ecto_backup, repos: [MyApp.Repo]

          # When running the mix task
          mix ecto_backup.restore -r MyApp.Repo

          # When running the release task
          ./restore --repo MyApp.Repo
      """
  end

  defp message_for(:mismatched_backup_file_count, %{value: {repo_count, file_count}}) do
    "mismatched number of repos and backup files provided, got #{repo_count} repos but " <>
      "#{file_count} backup files, please ensure that the number of backup files matches " <>
      "the number of repos being backed up or restored"
  end

  defp message_for(:mismatched_restore_file_count, %{value: {repo_count, file_count}}) do
    "mismatched number of repos and restore files provided, got #{repo_count} repos but " <>
      "#{file_count} restore files, please ensure that the number of restore files matches " <>
      "the number of repos being backed up or restored"
  end

  defp message_for(:invalid_backup_file_list, %{value: invalid}) do
    "invalid :files option for backup, expected a list of strings, got #{inspect(invalid)}"
  end

  defp message_for(:invalid_restore_file_list, %{value: invalid}) do
    "invalid :files option for restore, expected a list of strings, got #{inspect(invalid)}"
  end

  defp message_for(:no_restore_file_found, %{repo: repo, value: restore_dir}) do
    "no backup files found in restore directory #{inspect(restore_dir)} for repo " <>
      "#{inspect(repo)}, please ensure that the directory exists and contains valid backup " <>
      "files, or specify a valid :restore_file in the repo configuration\n\n" <>
      """
      Examples:

          # In app config
          config :ecto_backup, restore_dir: "/path/to/restore/dir"

          # When running the mix task
          mix ecto_backup.restore -d /path/to/restore/dir -f /path/to/backup/file

          # When running the release task
          ./restore --restore-dir /path/to/restore/dir -f /path/to/backup/file
      """
  end

  defp message_for(:nonexistent_restore_file, %{repo: repo, value: restore_file}) do
    "restore file #{inspect(restore_file)} for repo #{inspect(repo)} does not exist or is " <>
      "not readable"
  end

  defp message_for(:restore_not_confirmed, %{repo: repo}) do
    "restore operation for repo #{inspect(repo)} was not confirmed, aborting restore"
  end

  defp message_for(:invalid_backup_schedule, %{repo: repo, value: value}) do
    "invalid :backup_schedule format for repo #{inspect(repo)}, please provide a valid cron " <>
      "expression string or Crontab.CronExpression struct for scheduling backups\n\n" <>
      """
      Got value:

          #{inspect(value)}

      Examples:

          # Valid cron expression strings
          "0 2 * * *"        # every day at 2am
          "0 */6 * * *"      # every 6 hours
          "30 1 * * 1-5"     # at 1:30am on weekdays

          # Using Crontab.CronExpression struct
          %Crontab.CronExpression{expression: "0 2 * * *"}

          # Using Crontab.CronExpression ~e[] sigil
          import Crontab.CronExpression
          ~e[0 2 * * *]
      """
  end

  defp message_for(:invalid_backup_stagger_sec, %{repo: repo, value: value}) do
    "invalid :backup_stagger_sec value for repo #{inspect(repo)}, " <>
      "expected a non-negative integer\n\n" <>
      """
      Got value:

          #{inspect(value)}
      """
  end

  defp message_for(:invalid_backup_node, %{repo: repo, value: value}) do
    """
    invalid :backup_node value for repo #{inspect(repo)}, expected an atom, nil, or a list of atoms

    Got value:
        #{inspect(value)}
    """
  end

  # If this is reached then you forgot to define a message for the given reason
  defp message_for(reason, opts) do
    raise "no message given for unknown ConfError #{inspect(reason)} with #{inspect(opts)}"
  end
end
