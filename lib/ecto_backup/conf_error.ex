defmodule EctoBackup.ConfError do
  @moduledoc """
  Exception module for EctoBackup configuration errors.
  """
  defexception [:reason, :repo, :value, :message]

  @type t :: %__MODULE__{
          reason: atom(),
          repo: Ecto.Repo.t() | nil,
          value: term() | nil,
          message: String.t() | nil
        }

  @impl true
  def message(%{message: message}) when is_binary(message), do: message

  def message(%{reason: :invalid_repo_list, value: repo_list}) do
    """
    invalid :repos configuration, expected a list of repo modules
    or {module, config} tuples

    Got value:

        #{inspect(repo_list)}
    """
  end

  def message(%{reason: :no_default_repos}) do
    """
    no default repositories found, please configure :repos in
    the :ecto_backup application configuration

    Examples:

        # In app config
        config :ecto_backup, repos: [MyApp.Repo]

        # When running the mix task
        mix ecto_backup.backup -r MyApp.Repo

        # When running the release task
        ./backup --repo MyApp.Repo
    """
  end

  def message(%{reason: :invalid_repo_spec, value: repo_spec}) do
    "invalid repo specification, expected atom or {module, keyword}, got: #{inspect(repo_spec)}"
  end

  def message(%{reason: :invalid_repo_config, repo: repo, value: config}) do
    "invalid repo config returned from #{inspect(repo)}.config/0, got: #{inspect(config)}"
  end

  def message(%{reason: :invalid_repo, repo: repo}) do
    "#{inspect(repo)} is not a valid Ecto.Repo module"
  end

  def message(%{reason: :invalid_backup_file, value: invalid}) do
    "invalid backup file path, expected a string, got #{inspect(invalid)}"
  end

  def message(%{reason: :invalid_backup_dir, value: invalid}) do
    "invalid backup directory path, expected a string, got #{inspect(invalid)}"
  end

  def message(%{reason: :no_backup_dir_set}) do
    """
    no backup directory is set, so a backup file cannot
    be generated, please set the :backup_dir option or specify
    a :backup_file in the repo configuration

    Examples:

        # In app config
        config :ecto_backup, backup_dir: "/path/to/backup/dir"

        # When running the mix task
        mix ecto_backup.backup -d /path/to/backup/dir

        # When running the release task
        ./backup --backup-dir /path/to/backup/dir
    """
  end

  def message(%{reason: :no_repos_to_backup}) do
    """
    no repositories to back up, please provide at
    least one repository in the :repos option or configure :repos in the
    :ecto_backup application configuration

    Examples:

        # In app config
        config :ecto_backup, repos: [MyApp.Repo]

        # When running the mix task
        mix ecto_backup.backup -r MyApp.Repo

        # When running the release task
        ./backup --repo MyApp.Repo
    """
  end

  def message(%{reason: :no_repos_to_restore}) do
    """
    no repositories to restore, please provide at
    least one repository in the :repos option or configure :repos in the
    :ecto_backup application configuration

    Examples:

        # In app config
        config :ecto_backup, repos: [MyApp.Repo]

        # When running the mix task
        mix ecto_backup.restore -r MyApp.Repo path/to/backup/file

        # When running the release task
        ./restore --repo MyApp.Repo path/to/backup/file
    """
  end

  def message(%{reason: :multiple_repos_to_restore}) do
    """
    multiple repositories provided for restore,
    please provide only one repository in the :repos option when restoring
    a backup file

    Examples:

        # In app config
        config :ecto_backup, repos: [MyApp.Repo]

        # When running the mix task
        mix ecto_backup.restore -r MyApp.Repo path/to/backup/file

        # When running the release task
        ./restore --repo MyApp.Repo path/to/backup/file
    """
  end

  def message(%{reason: :invalid_backup_schedule, repo: repo, value: value}) do
    """
    invalid :backup_schedule format for repo #{inspect(repo)},
    please provide a valid cron expression string or Crontab.CronExpression struct for
    scheduling backups

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

  def message(%{reason: :invalid_backup_stagger, repo: repo, value: value}) do
    """
    invalid :backup_stagger value for repo #{inspect(repo)}, expected a non-negative integer

    Got value:

        #{inspect(value)}
    """
  end

  def message(%{reason: :invalid_backup_node, repo: repo, value: value}) do
    """
    invalid :backup_node value for repo #{inspect(repo)}, expected an atom, nil, or a list of atoms

    Got value:
        #{inspect(value)}
    """
  end
end
