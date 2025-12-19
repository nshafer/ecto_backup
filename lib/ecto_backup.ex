defmodule EctoBackup do
  @moduledoc """
  EctoBackup provides functionality to back up and restore Ecto repositories.

  This module is the main interface for performing backup and restore operations, and is what the
  mix tasks, release tasks, and scheduled jobs use for their main functionality. As such these
  functions are generic and provide hooks and telemetry events for those higher level interfaces
  to build upon.

  For most use cases, these functions are not used directly, but rather through the mix tasks when
  in a development environment, or through release tasks or scheduled jobs in production
  environments. See the `Mix.Tasks.EctoBackup.Backup` and `Mix.Tasks.EctoBackup.Restore` modules
  for more information on the mix tasks. See the `EctoBackup.Release` module for release
  information and the `Mix.Tasks.EctoBackup.Gen.Release` module for generating helper scripts for
  releases.

  > #### Warning {: .warning}
  >
  > This library provides simple backup and restore functionality for Ecto repositories, it may
  > not be a complete backup solution for all use cases. It is recommended to evaluate your
  > specific backup and restore requirements and ensure that this library meets those needs before
  > relying on it for critical data protection. Always test your backups and restores to ensure
  > they work as expected. Always keep your backups secure and follow best practices for data
  > protection.

  ## Individual Repo Configuration

  Database Configuration for each repo, such as username, hostname, database, password, is
  gathered from multiple sources, each merging with and overriding the previous one:

    1. The configuration returned by the repo's `config/0` function. This is the base
       configuration, and is usually defined in your project configuration files or an `init/2`
       callback in the repo module.

           # config/dev.exs
           config :myapp, Myapp.Repo,
             username: "postgres",
             password: "postgres",
             hostname: "localhost",
             database: "myapp_dev"

    2. Overrides on a per-repo basis in the `:ecto_backup` application environment. This allows
       you to specify different settings for backup/restore operations without changing the main
       repo configuration.

           # config/prod.exs
           config :ecto_backup, MyApp.Repo,
             username: "backup_user",
             adapter: EctoBackup.Adapters.Postgres

    3. Options provided directly when invoking backup/restore functions. See `backup/1` and
       `restore/1` for details.

           EctoBackup.backup(
             repos: [
               {MyApp.Repo,
                 username: "readonly_user",
                 backup_file: "/tmp/backup.db"}
              ]
            )

  The exact configuration needed for each repo will depend on the adapter and database
  configuration. Ecto generally requires at least `:database` is set, but often `:username`,
  `:password`, and `:hostname` are also needed. Other adapter-specific options may also be given,
  such as `:port`, `:socket`, or SSL options.

  Additionally, EctoBackup specific options can be set in the same way, such as:

    - `:backup_file` to specify exactly what file to write to. Can be a string, 2-arity function
      that takes the repo and repo_config and returns a string, or a MFA tuple to a function that
      takes args prepended with the repo and repo_config and returns a string.
    - `:adapter` to specify which backup adapter to use instead of auto-detecting from the repo's
      adapter.

  """

  alias EctoBackup.Adapter
  alias EctoBackup.Util

  @type backup_result :: {:ok, String.t()} | {:error, term()}

  @doc """
  Initiates a backup of one or more Ecto repositories.

  This will attempt to validate the configuration first, and return an error in the form of
  `{:error, EctoBackup.ConfError{}}` if any configuration issues are found. If all configuration
  is valid, it will attempt to back up each repository in turn via the appropriate adapter,
  returning a list of results for each repo. If any repo backup fails, the overall operation will
  still attempt to continue to back up the remaining repos.

  Returns `{:ok, list_of_results}` as long as any backups were attempted, but may contain errors
  in the results. Each result in the list will be either `{:ok, repo, backup_file}` or `{:error,
  repo, reason}` depending on whether that specific repo backup succeeded or failed.

  Returns `{:error, reason}` where `reason` is a `EctoBackup.Error` or `EctoBackup.ConfError` on
  any general errors that prevent backups from being attempted.

  ## Options

    - `:repos` - A list of repositories to back up. This may be a list of module names, or a list
      of `{repo, repo_options}` tuples to override options for specific repos. See the [Individual
      Repo Configuration](`EctoBackup#module-individual-repo-configuration`) section for more
      details. If not provided, the default repositories from the application configuration will
      be used.

    - `:backup_dir` - The directory where backup files will be stored if not individually
      specified. This directory must exist and be writable before calling this function. Can be a
      string, 2-arity function that takes `repo` and `repo_config` and returns a string, or a MFA
      tuple to a function that takes args prepended with the `repo` and `repo_config` and returns
      a string.

    - Other options may be provided which will be passed to the adapter's backup function. See the
      documentation for the specific adapter being used for more details on supported options.

  ## Examples:

      # Backup default repos from application config
      {:ok, results} = EctoBackup.backup()

      # Backup specific repos
      {:ok, results} = EctoBackup.backup(repos: [MyApp.Repo, MyApp.AnotherRepo])

      # Backup with overridden options for a specific repo
      {:ok, results} = EctoBackup.backup(
        backup_dir: "/custom/backup/dir",
        repos: [
          MyApp.Repo,
          {MyApp.AnotherRepo, backup_file: "/tmp/export.db"},
          {MyApp.YetAnotherRepo, username: "readonly_user"},
        ]
      )

  ## Configuration

  Typically the backup configuration is set in your application's configuration files so that the
  various methods of invoking backups (mix tasks, release tasks, scheduled jobs) can all share the
  same configuration. Example:

      config :ecto_backup,
        repos: [MyApp.Repo, MyApp.AnotherRepo],
        backup_dir: "/var/backups/myapp"

      config :ecto_backup, MyApp.Repo,
        username: "backup_user",
        adapter: CustomBackupAdapter

      config :ecto_backup, MyApp.AnotherRepo,
        backup_dir: "/mnt/backup_drive/myapp"

  ## Telemetry Events

  During backup and restore operations, the following telemetry events are emitted:

    - `[:ecto_backup, :backup, :start]` - Emitted at the start of a backup operation.

    - `[:ecto_backup, :backup, :stop]` - Emitted at the end of a backup operation, includes
      `:duration` in measurements and the `:result` in metadata.

    - `[:ecto_backup, :backup, :exception]` - Emitted if an unhandled exception occurs during the
      backup operation. Metadata includes everything in the `:start` event plus `:kind`,
      `:reason`, and `:stacktrace`. Measurements includes `:duration` but no `:result`.

    - `[:ecto_backup, :backup, :repo, :start]` - Emitted at the start of a repo-specific backup
      operation. Includes the `:repo`, `:repo_config`, and `:backup_file` in metadata.

    - `[:ecto_backup, :backup, :repo, :stop]` - Emitted at the end of a repo-specific backup
      operation. Includes the `:repo`, `:repo_config`, `:backup_file`, and `:result` in metadata.

    - `[:ecto_backup, :backup, :repo, :exception]` - Emitted if an unhandled exception occurs
      during a repo-specific backup operation. Metadata includes everything in the `:start` event
      plus `:kind`, `:reason`, and `:stacktrace`. Measurements includes `:duration` but no
      `:result`.

  Additional telemetry events may be emitted by specific adapters during their operations such as
  the recommend `[:ecto_backup, :backup, :repo, :message]` and `[:ecto_backup, :backup, :repo,
  :progress]` events in `EctoBackup.Adapter`.
  """
  @spec backup(keyword() | map()) :: {:ok, [backup_result()]} | {:error, term()}
  def backup(opts \\ %{}) do
    options = Map.new(opts)

    with(
      {:ok, repo_specs} <- Util.get_repo_specs(options),
      {:ok, repo_configs} <- Util.get_repo_configs(repo_specs),
      {:ok, backup_files} <- Util.get_backup_files(repo_configs, options)
    ) do
      metadata = %{repos: repo_configs, options: options}

      :telemetry.span([:ecto_backup, :backup], metadata, fn ->
        results =
          for {{repo, repo_config}, backup_file} <- Enum.zip(repo_configs, backup_files) do
            do_repo_backup(repo, repo_config, backup_file, options)
          end

        {{:ok, results}, Map.put(metadata, :results, results)}
      end)
    end
  end

  defp do_repo_backup(repo, repo_config, backup_file, options) do
    metadata = %{repo: repo, repo_config: repo_config, backup_file: backup_file, options: options}

    :telemetry.span([:ecto_backup, :backup, :repo], metadata, fn ->
      result =
        case Adapter.backup(repo, repo_config, backup_file, options) do
          {:ok, file} -> {:ok, repo, file}
          {:error, error} -> {:error, repo, error}
        end

      {result, Map.put(metadata, :result, result)}
    end)
  end

  @doc """
  Same as `backup/1`, but raises an `EctoBackup.Error` if the overall backup operation fails or
  if any individual repo backup fails.

  If any repo backup fails, an error will not be raised immediately, and all backups will still be
  attempted, then after all backups are complete, if any failed, an error will be raised.

  Returns a list of results for each repo backup in the form `{repo, backup_file}` if all backups
  succeeded.
  """
  @spec backup!(keyword() | map()) :: [backup_result()]
  def backup!(opts \\ %{}) do
    case backup(opts) do
      {:ok, results} ->
        errors =
          Enum.filter(results, fn
            {:error, _repo, _reason} -> true
            _ -> false
          end)

        if errors != [] do
          error_detail =
            for {:error, repo, error} <- errors, into: "" do
              "#{inspect(repo)}: #{Exception.message(error)}\n"
            end

          raise EctoBackup.Error, "One or more repository backups failed:\n" <> error_detail
        else
          results
        end

      {:error, reason} ->
        raise EctoBackup.Error, "Backup failed: #{inspect(reason)}"
    end
  end

  @doc """
  Restores a backup for a single Ecto repository from the specified file.

  This will attempt to validate the configuration first, and return an error if any configuration
  issues are found. If all configuration is valid, it will attempt to restore the repository from
  the given backup file via the appropriate adapter.

  Returns `{:ok, repo}` on success, `{:error, reason}` on general failure or `{:error, repo,
  reason}` if the adapter fails to restore the repo.

  ## Options

    - `:repo` - The repository to restore. This option is required if more than one repository is
      configured in the application environment. This may be a module name or a `{repo,
      repo_options}` tuple. See the [Individual Repo
      Configuration](`EctoBackup#module-individual-repo-configuration`) section for more details.

    - `:confirm` - Must be set to `true` or a confirmation prompt function must be provided to
      confirm the restore operation. This is to prevent accidental restores which could lead to
      data loss. The confirmation prompt function should be a zero-arity function that returns
      `true` to confirm or `false` to cancel, or an MFA tuple to a function that returns `true` or
      `false`.

    - Other options may be provided which will be passed to the adapter's restore function. See
      the documentation for the specific adapter being used for more details on supported options.

  ## Examples:

      # Restore a specific repo from a backup file
      EctoBackup.restore("/path/to/backup.db", repo: MyApp.Repo, confirm: true)

      # Restore with overridden options
      EctoBackup.restore(
        "/path/to/backup.db",
        repo: {MyApp.Repo,
          username: "restore_user",
          confirm: {MyApp.Prompts, :confirm_restore, []}}
      )

  ## Configuration

  Unless specified with `repo`, this will attempt to get a default repository to restore from the
  `:ecto_backup` application configuration. If more than one repository is configured, the `:repo`
  option must be provided.

  ## Telemetry Events

  During backup and restore operations, the following telemetry events are emitted:

    - `[:ecto_backup, :restore, :start]` - Emitted at the start of a restore operation.

    - `[:ecto_backup, :restore, :stop]` - Emitted at the end of a restore operation, includes
      `:duration` in measurements and the `:result` in metadata.

    - `[:ecto_backup, :restore, :repo, :start]` - Emitted at the start of a repo-specific restore
      operation. Includes the `:repo`, `:repo_config`, and `:restore_file` in metadata.

    - `[:ecto_backup, :restore, :repo, :stop]` - Emitted at the end of a repo-specific restore
      operation. Includes the `:repo`, `:repo_config`, `:restore_file`, and `:result` in metadata.

  Additional telemetry events may be emitted by specific adapters during their operations.
  """
  @spec restore(String.t(), keyword() | map()) ::
          {:ok, module()} | {:error, term()} | {:error, module(), term()}
  def restore(restore_file, opts \\ %{}) do
    options = Map.new(opts)

    with(
      {:ok, repo_spec} <- Util.get_repo_spec(options),
      {:ok, [{repo, repo_config}]} <- Util.get_repo_configs([repo_spec]),
      {:ok, restore_file} <- Util.ensure_restore_file(restore_file),
      :ok <- Util.ensure_restore_confirmed(repo, repo_config, options)
    ) do
      metadata = %{repo: {repo, repo_config}, restore_file: restore_file, options: options}

      :telemetry.span([:ecto_backup, :restore], metadata, fn ->
        result = do_repo_restore(repo, repo_config, restore_file, options)

        {result, Map.put(metadata, :result, result)}
      end)
    end
  end

  defp do_repo_restore(repo, repo_config, restore_file, options) do
    metadata = %{
      repo: repo,
      repo_config: repo_config,
      restore_file: restore_file,
      options: options
    }

    :telemetry.span([:ecto_backup, :restore, :repo], metadata, fn ->
      result =
        case Adapter.restore(repo, repo_config, restore_file, options) do
          :ok -> {:ok, repo}
          {:error, error} -> {:error, repo, error}
        end

      {result, Map.put(metadata, :result, result)}
    end)
  end

  @doc """
  Same as `restore/2`, but raises an `EctoBackup.Error` if the restore operation fails.

  Returns the restored Repo on success, or raises an error on failure.
  """
  @spec restore!(String.t(), keyword() | map()) :: {:ok, module()} | {:error, module(), term()}
  def restore!(restore_file, opts \\ %{}) do
    case restore(restore_file, opts) do
      {:ok, repo} ->
        repo

      {:error, reason} ->
        raise EctoBackup.Error, "Restore failed: #{inspect(reason)}"

      {:error, repo, reason} ->
        raise EctoBackup.Error,
              "Restore for #{inspect(repo)} failed: #{Exception.message(reason)}"
    end
  end
end
