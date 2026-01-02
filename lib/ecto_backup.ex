defmodule EctoBackup do
  @moduledoc """
  EctoBackup provides functionality to back up and restore Ecto repositories.

  This module is the main interface for performing backup and restore operations, and is what the
  mix tasks, release tasks, and scheduled jobs use for their main functionality. As such these
  functions are generic and provide hooks and `m::telemetry` events for those higher level
  interfaces to build upon.

  For most use cases, these functions are not used directly, but rather through the mix tasks when
  in a development environment, or through release tasks or scheduled jobs in production
  environments. See the `Mix.Tasks.EctoBackup.Backup` and `Mix.Tasks.EctoBackup.Restore` modules
  for more information on the mix tasks. See the `Mix.Tasks.EctoBackup.Gen.Release` module for
  generating helper scripts for releases and the `EctoBackup.Release` module for more information.

  > #### Warning {: .warning}
  >
  > This library provides simple backup and restore functionality for Ecto repositories, it may
  > not be a complete backup solution for all use cases. It is recommended to evaluate your
  > specific backup and restore requirements and ensure that this library meets those needs before
  > relying on it for critical data protection. Always test your backups and restores to ensure
  > they work as expected. Always keep your backups secure and follow best practices for data
  > protection.

  ## Individual Repo Configuration

  Database Configuration for each repo, such as username, hostname, database name, etc is gathered
  from multiple sources, each merging with and overriding the previous one:

    1. The configuration for each Ecto Repo as returned by the repo's `config/0` function. This is
       the base configuration, and is usually defined in your project configuration files or an
       `init/2` callback in the repo module.

           # config/dev.exs
           config :myapp, Myapp.Repo,
             username: "postgres",
             password: "postgres",
             hostname: "localhost",
             database: "myapp_dev"

    2. Overrides on a per-repo basis in the `:ecto_backup` application environment. This allows
       you to specify different settings for backup/restore operations without changing the main
       repo configuration for Ecto.

           # config/prod.exs
           config :ecto_backup, MyApp.Repo,
             username: "backup_user",
             adapter: MyCustomBackupAdapter

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

  Additionally, EctoBackup specific options can be set in the same way. See `backup/1` and
  `restore/1` for details on the options that can be set per-repo for those operations. There are
  also specific options for `EctoBackup.Scheduler` if using scheduled backups.

  Global options:

    - `:adapter` to specify which backup adapter to use instead of auto-detecting from the repo's
      adapter. This must be a module that implements the `EctoBackup.Adapter` behaviour.

  """

  alias EctoBackup.Adapter
  alias EctoBackup.Util

  @type backup_result :: {:ok, String.t()} | {:error, term()}
  @type restore_result :: {:ok, String.t()} | {:error, term()}

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

  Returns `{:error, reason}` where `reason` is an `EctoBackup.Error` or `EctoBackup.ConfError` on
  any general errors that prevent backups from being attempted.

  ## Options

    - `:repos` - A list of repositories to back up. This may be a list of module names, or a list
      of `{repo, repo_options}` tuples to override options for specific repos. See the [Individual
      Repo Configuration](`EctoBackup#module-individual-repo-configuration`) section for more
      details. If not provided, the default `:ecto_repos` from the application configuration will
      be used.

    - `:files` - A list of backup files to back up to, corresponding to the repos in `:repos`.
      This must be a list of strings. If provided, the length of this list must match the length
      of the `:repos` list. If not provided, backup files will be determined based on the
      individual repo `:backup_file` options if specified, otherwise a default filename will be
      constructed and stored in the `:backup_dir`.

    - `:backup_dir` - The directory where backup files will be stored if not individually
      specified in `:repos` or global config. This is required if individual `:backup_file` repo
      options are not provided for all repos. If a specific `:backup_file` is not provided for a
      repo, a default filename will be constructed using the current timestamp and the repo name
      and stored in this directory, which must exist and be writable. Can be a string, 2-arity
      function that takes `repo` and `repo_config` and returns a string, or an MFA tuple to a
      function that takes args prepended with the `repo` and `repo_config` and returns a string.

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
        adapter: CustomEctoBackupAdapter

      config :ecto_backup, MyApp.AnotherRepo,
        backup_dir: "/mnt/backup_drive/myapp"

  ## Telemetry Events

  During backup the following `m::telemetry` events are emitted:

    - `[:ecto_backup, :backup, :start]` - Emitted at the start of the entire backup operation.
      Metadata includes a `repos` list, which is a list of 2-tuples of `{repo, repo_config}` for
      each repo being backed up, and the `options` provided for the overall backup operation.

    - `[:ecto_backup, :backup, :stop]` - Emitted at the end of the entire backup operation.
      Measurements includes `:duration`. Metadata includes everything in the `:start` event plus
      the `:results` list.

    - `[:ecto_backup, :backup, :exception]` - Emitted if an unhandled exception occurs during the
      backup operation. Metadata includes everything in the `:start` event plus `:kind`,
      `:reason`, and `:stacktrace`. Measurements includes `:duration` but no `:result`.

    - `[:ecto_backup, :backup, :repo, :start]` - Emitted at the start of each repo backup
      operation. Metadata includes the `:repo` and `:repo_config`, and `:options`. The
      `:backup_file` is available in the `:repo_config`.

    - `[:ecto_backup, :backup, :repo, :stop]` - Emitted at the end of each repo backup operation.
      Metadata includes everything in the `:start` event plus the `:result` for this repo.

    - `[:ecto_backup, :backup, :repo, :exception]` - Emitted if an unhandled exception occurs
      during a repo-specific backup operation. Metadata includes everything in the `:start` event
      plus `:kind`, `:reason`, and `:stacktrace`. Measurements includes `:duration` but no
      `:result`.

  Additional `m::telemetry` events may be emitted by specific adapters during their operations
  such as the recommend `[:ecto_backup, :backup, :repo, :message]` and `[:ecto_backup, :backup,
  :repo, :progress]` events in `EctoBackup.Adapter`.
  """
  @spec backup(keyword() | map()) :: {:ok, [backup_result()]} | {:error, term()}
  def backup(opts \\ %{}) do
    options = Map.new(opts)

    with(
      {:ok, repo_specs} <- Util.get_repo_specs(:backup, options),
      {:ok, repo_configs} <- Util.get_repo_configs(:backup, repo_specs),
      {:ok, repo_configs} <- Util.get_backup_files(repo_configs, options)
    ) do
      metadata = %{repos: repo_configs, options: options}

      :telemetry.span([:ecto_backup, :backup], metadata, fn ->
        results =
          for {repo, repo_config} <- repo_configs do
            do_repo_backup(repo, repo_config, options)
          end

        {{:ok, results}, Map.put(metadata, :results, results)}
      end)
    end
  end

  defp do_repo_backup(repo, repo_config, options) do
    metadata = %{repo: repo, repo_config: repo_config, options: options}

    :telemetry.span([:ecto_backup, :backup, :repo], metadata, fn ->
      result =
        case Adapter.backup(repo, repo_config, options) do
          {:ok, file} -> {:ok, repo, file}
          {:error, error} -> {:error, repo, error}
        end

      {result, Map.put(metadata, :result, result)}
    end)
  end

  @doc """
  Same as `backup/1`, but raises an `EctoBackup.Error` if the overall backup operation fails or if
  any individual repo backup fails.

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
  Initiates a restore of one or more Ecto repositories from backup files.

  This will attempt to validate the configuration first, and return an error in the form of
  {:error, EctoBackup.ConfError{}} if any configuration issues are found. If all configuration is
  valid, it will attempt to restore each repository in turn via the appropriate adapter, returning
  a list of results for each repo. If any repo restore fails, the overall operation will still
  attempt to continue to restore the remaining repos.

  Returns `{:ok, list_of_results}` as long as any restores were attempted, but may contain errors
  in the results. Each result in the list will be either {:ok, repo, restore_file} or {:error,
  repo, reason} depending on whether that specific repo restore succeeded or failed.

  Returns `{:error, reason}` where `reason` is an `EctoBackup.Error` or `EctoBackup.ConfError` on
  any general errors that prevent restores from being attempted.

  ## Options

    - `:repos` - A list of repositories to restore. This may be a list of module names, or a list
      of `{repo, repo_options}` tuples to override options for specific repos. See the [Individual
      Repo Configuration](`EctoBackup#module-individual-repo-configuration`) section for more
      details. If not provided, the default `:ecto_repos` from the application configuration will
      be used.

    - `:files` - A list of backup files to restore from, corresponding to the repos in `:repos`.
      This must be a list of strings. If provided, the length of this list must match the length
      of the `:repos` list. If not provided, restore files will be determined based on the
      individual repo `:restore_file` options if specified, otherwise the latest backup file found
      in `:restore_dir` will be used for each repo.

    - `:restore_dir` - The directory where the latest backup file will be restored from if not
      individually specified. If not provided, defaults to the `:backup_dir` global configuration.
      This is required if individual `:restore_file` repo options are not provided for all repos.
      If a specific `:restore_file` is not provided for a repo, the latest backup file will be
      located in  this directory that matches the default backup filename pattern. This directory
      must exist and be readable before calling this function. Can be a string, 2-arity function
      that takes `repo` and `repo_config` and returns a string, or an MFA tuple to a function that
      takes args prepended with the `repo` and `repo_config` and returns a string.

    - `:confirm` - Must be a list of repos to confirm restores for, a 2-arity function that takes
      `repo` and `repo_config` and returns `true` to confirm or `false` to cancel, or an MFA tuple
      to a function that takes args prepended with the `repo` and `repo_config` and returns `true`
      or `false`. Each repo being restored will call the confirmation function to confirm the
      restore operation before proceeding.  This is to prevent accidental restores which could
      lead to data loss.

    - Other options may be provided which will be passed to the adapter's restore function. See
      the documentation for the specific adapter being used for more details on supported options.

  ## Examples:

      # Restore default repos from application config
      {:ok, results} = EctoBackup.restore()

      # Restore a specific repo from a backup file
      {:ok, results} = EctoBackup.restore(
        repos: [MyApp.Repo],
        files: ["/path/to/backup.db"],
        confirm: [MyApp.Repo]
      )

      # Restore with overridden options
      EctoBackup.restore(
        repos: [{MyApp.Repo,
          username: "restore_user",
          restore_file: {Myapp.BackupFinder, :latest_backup_file, []}}],
          confirm: {MyApp.Prompts, :confirm_restore, []}}]
      )

  ## Configuration

  Typically the restore configuration is set in your application's configuration files so that the
  various methods of invoking restores (mix tasks, release tasks) can all share the same
  configuration. Example:

      # NOTE: backup_dir is used as the default restore_dir if not explicitly set
      config :ecto_backup,
        repos: [MyApp.Repo, MyApp.AnotherRepo],
        backup_dir: "/var/backups/myapp"

      config :ecto_backup, MyApp.Repo,
        username: "restore_user",
        adapter: CustomEctoBackupAdapter

      config :ecto_backup, MyApp.AnotherRepo,
        restore_dir: "/mnt/backup_drive/myapp"

  ## Telemetry Events

  During restore the following `m::telemetry` events are emitted:

    - `[:ecto_backup, :restore, :start]` - Emitted at the start of the entire restore operation.
      Metadata includes a `repos` list, which is a list of 2-tuples of `{repo, repo_config}` for
      each repo being restored, and the `options` provided for the overall restore operation.

    - `[:ecto_backup, :restore, :stop]` - Emitted at the end of the entire restore operation.
      Measurements includes `:duration`. Metadata includes everything in the `:start` event plus
      the `:results` list.

    - `[:ecto_backup, :restore, :exception]` - Emitted if an unhandled exception occurs during the
      restore operation. Metadata includes everything in the `:start` event plus `:kind`,
      `:reason`, and `:stacktrace`. Measurements includes `:duration` but no `:result`.

    - `[:ecto_backup, :restore, :repo, :start]` - Emitted at the start of each repo restore
      operation. Metadata includes the `:repo` and `:repo_config`, and `:options`. The
      `:restore_file` is available in the `:repo_config`.

    - `[:ecto_backup, :restore, :repo, :stop]` - Emitted at the end of each repo restore
      operation. Metadata includes everything in the `:start` event plus the `:result` for this
      repo.

    - `[:ecto_backup, :restore, :repo, :exception]` - Emitted if an unhandled exception occurs
      during a repo-specific restore operation. Metadata includes everything in the `:start` event
      plus `:kind`, `:reason`, and `:stacktrace`. Measurements includes `:duration` but no
      `:result`.

  Additional `m::telemetry` events may be emitted by specific adapters during their operations
  such as the recommend `[:ecto_backup, :restore, :repo, :message]` and `[:ecto_backup, :restore,
  :repo, :progress]` events in `EctoBackup.Adapter`.
  """
  @spec restore(keyword() | map()) :: {:ok, [restore_result()]} | {:error, term()}
  def restore(opts \\ %{}) do
    options = Map.new(opts)

    with(
      {:ok, repo_specs} <- Util.get_repo_specs(:restore, options),
      {:ok, repo_configs} <- Util.get_repo_configs(:restore, repo_specs),
      {:ok, repo_configs} <- Util.get_restore_files(repo_configs, options),
      :ok <- Util.ensure_restore_files(repo_configs),
      :ok <- Util.ensure_restores_confirmed(repo_configs, options)
    ) do
      metadata = %{repos: repo_configs, options: options}

      :telemetry.span([:ecto_backup, :restore], metadata, fn ->
        results =
          for {repo, repo_config} <- repo_configs do
            do_repo_restore(repo, repo_config, options)
          end

        {{:ok, results}, Map.put(metadata, :results, results)}
      end)
    end
  end

  defp do_repo_restore(repo, repo_config, options) do
    metadata = %{
      repo: repo,
      repo_config: repo_config,
      options: options
    }

    :telemetry.span([:ecto_backup, :restore, :repo], metadata, fn ->
      result =
        case Adapter.restore(repo, repo_config, options) do
          {:ok, file} -> {:ok, repo, file}
          {:error, error} -> {:error, repo, error}
        end

      {result, Map.put(metadata, :result, result)}
    end)
  end

  @doc """
  Same as `restore/2`, but raises an `EctoBackup.Error` if the overall restore operation fails or
  if any individual repo restore fails.

  If any repo restore fails, an error will not be raised immediately, and all restores will still
  be attempted, then after all restores are complete, if any failed, an error will be raised.

  Returns a list of results for each repo restore in the form `{repo, restore_file}` if all
  restores succeeded.
  """
  @spec restore!(keyword() | map()) :: [restore_result()]
  def restore!(opts \\ %{}) do
    case restore(opts) do
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
        raise EctoBackup.Error, "Restore failed: #{inspect(reason)}"
    end
  end
end
