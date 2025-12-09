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
  > This library provides simple backup and restore functionality for Ecto repositories, but it is
  > not intended to be a complete backup solution for all use cases. It is recommended to evaluate
  > your specific backup and restore requirements and ensure that this library meets those needs
  > before relying on it for critical data protection. Always test your backups and restores to
  > ensure they work as expected. Always keep your backups secure and follow best practices for data
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
  alias EctoBackup.Conf
  alias EctoBackup.ConfError
  alias EctoBackup.Error

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
      {:ok, repo_specs, options} <- get_repo_specs(options),
      {:ok, repo_configs} <- get_repo_configs(repo_specs),
      {:ok, backup_files} <- get_backup_files(repo_configs, options)
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
  def restore(restore_file, opts \\ %{}) do
    options = Map.new(opts)

    with(
      {:ok, repo_spec, options} <- get_repo_spec(options),
      {:ok, [{repo, repo_config}]} <- get_repo_configs([repo_spec]),
      {:ok, restore_file} <- ensure_restore_file(restore_file),
      :ok <- ensure_restore_confirmed(repo, repo_config, options)
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

  # Retrieves the repository specifications from the provided options or application environment.
  # Returns a list of repo specifications or an error if the configuration is invalid.
  defp get_repo_specs(%{repos: repo_specs} = options) when is_list(repo_specs) do
    {:ok, repo_specs, Map.delete(options, :repos)}
  end

  defp get_repo_specs(%{repos: repo_specs}) do
    {:error, ConfError.exception(reason: :invalid_repo_list, value: repo_specs)}
  end

  defp get_repo_specs(options) do
    case Application.fetch_env(:ecto_backup, :repos) do
      {:ok, []} -> {:error, ConfError.exception(reason: :no_repos_to_backup)}
      {:ok, repos} when is_list(repos) -> {:ok, repos, options}
      {:ok, invalid} -> {:error, ConfError.exception(reason: :invalid_repo_list, value: invalid)}
      :error -> {:error, ConfError.exception(reason: :no_default_repos)}
    end
  end

  # Retrieves a single repository specification from the provided options or application
  # environment. Returns the repo specification or an error if the configuration is invalid.
  defp get_repo_spec(%{repo: repo_spec} = options) do
    {:ok, repo_spec, Map.delete(options, :repo)}
  end

  defp get_repo_spec(options) do
    case Application.fetch_env(:ecto_backup, :repos) do
      {:ok, [repo_spec]} -> {:ok, repo_spec, options}
      {:ok, []} -> {:error, ConfError.exception(reason: :no_repos_to_restore)}
      {:ok, _multiple} -> {:error, ConfError.exception(reason: :multiple_repos_to_restore)}
      :error -> {:error, ConfError.exception(reason: :no_default_repos)}
    end
  end

  # Retrieves the repository configurations for the given list of repository specifications.
  # Merges configurations from the repo, application env, and overrides. Returns a list of
  # tuples of `{repo_module, merged_config}` or an error if any configuration is invalid.
  defp get_repo_configs([]) do
    {:error, ConfError.exception(reason: :no_repos_to_backup, value: [])}
  end

  defp get_repo_configs(repo_specs) when is_list(repo_specs) do
    {:ok, Enum.map(repo_specs, &merge_repo_configs!/1)}
  rescue
    e in ConfError ->
      {:error, e}
  end

  # Merges the configuration for a single repository specification from the repo, application env,
  # and overrides. Returns a tuple of `{repo_module, merged_config}` or raises `ConfError` if the
  # configuration is invalid.
  defp merge_repo_configs!(repo_spec) do
    {repo, override_config} =
      case repo_spec do
        {repo_module, config} when is_atom(repo_module) -> {repo_module, Map.new(config)}
        repo_module when is_atom(repo_module) -> {repo_module, %{}}
        other -> raise ConfError, reason: :invalid_repo_spec, value: other
      end

    repo_config = get_repo_config!(repo)
    app_repo_config = Application.get_env(:ecto_backup, repo, %{}) |> Map.new()

    merged_config =
      repo_config
      |> Map.merge(app_repo_config)
      |> Map.merge(override_config)

    {repo, merged_config}
  end

  # Retrieves the base configuration for the given repository module by calling its `config/0`
  # function. Raises `ConfError` if the repo module is invalid or returns an invalid
  # configuration.
  defp get_repo_config!(repo) do
    if Code.ensure_loaded?(repo) and function_exported?(repo, :config, 0) do
      case repo.config() do
        config when is_list(config) -> Map.new(config)
        config -> raise ConfError, reason: :invalid_repo_config, repo: repo, value: config
      end
    else
      raise ConfError, reason: :invalid_repo, repo: repo
    end
  end

  # Return a list of backup file paths for the given list of repo configurations and options. If
  # any repo configuration does not have a valid backup file path, returns an error.
  defp get_backup_files(repo_configs, options) do
    backup_files =
      for {repo, repo_config} <- repo_configs do
        get_backup_file!(repo, repo_config, options)
      end

    {:ok, backup_files}
  rescue
    e in ConfError ->
      {:error, e}
  end

  # Return the backup file path for the given repo configuration and options. If not
  # explicitly specified, constructs a default backup file path using the backup_dir
  # and a timestamped filename.
  defp get_backup_file!(repo, repo_config, options) do
    case Conf.fetch(repo_config, options, :backup_file) do
      {:ok, file} when is_binary(file) ->
        file

      {:ok, fun} when is_function(fun, 2) ->
        backup_file = fun.(repo, repo_config)

        if is_binary(backup_file) do
          backup_file
        else
          raise ConfError, reason: :invalid_backup_file, repo: repo, value: backup_file
        end

      {:ok, {m, f, a}} when is_atom(m) and is_atom(f) and is_list(a) ->
        backup_file = apply(m, f, [repo, repo_config] ++ a)

        if is_binary(backup_file) do
          backup_file
        else
          raise ConfError, reason: :invalid_backup_file, repo: repo, value: backup_file
        end

      {:ok, other} ->
        raise ConfError, reason: :invalid_backup_file, repo: repo, value: other

      :error ->
        default_backup_file!(repo, repo_config, options)
    end
  end

  # Constructs a default backup file path using the backup_dir and a timestamped filename.
  defp default_backup_file!(repo, repo_config, options) do
    backup_dir = get_backup_dir!(repo, repo_config, options)
    Path.join(backup_dir, "#{repo_to_filename(repo)}_backup_#{filename_timestamp()}.db")
  end

  # Retrieves the backup directory from the repo configuration or options. Raises `ConfError` if
  # the backup directory is not set or invalid.
  defp get_backup_dir!(repo, repo_config, options) do
    case Conf.fetch(repo_config, options, :backup_dir) do
      {:ok, backup_dir} when is_binary(backup_dir) ->
        backup_dir

      {:ok, fun} when is_function(fun, 2) ->
        backup_dir = fun.(repo, repo_config)

        if is_binary(backup_dir) do
          backup_dir
        else
          raise ConfError, reason: :invalid_backup_dir, repo: repo, value: backup_dir
        end

      {:ok, {m, f, a}} when is_atom(m) and is_atom(f) and is_list(a) ->
        backup_dir = apply(m, f, [repo, repo_config] ++ a)

        if is_binary(backup_dir) do
          backup_dir
        else
          raise ConfError, reason: :invalid_backup_dir, repo: repo, value: backup_dir
        end

      {:ok, invalid} ->
        raise ConfError, reason: :invalid_backup_dir, repo: repo, value: invalid

      :error ->
        raise ConfError, reason: :no_backup_dir_set, repo: repo
    end
  end

  # Returns a timestamp string suitable for filenames.
  defp filename_timestamp() do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
    |> String.replace(":", "-")
  end

  # Converts a repository module to a filename-friendly format.
  defp repo_to_filename(repo) do
    repo
    |> Module.split()
    |> Enum.map(&Macro.underscore/1)
    |> Enum.join("_")
  end

  # Ensures the restore file is valid and exists.
  defp ensure_restore_file(restore_file) when is_binary(restore_file) do
    if File.exists?(restore_file) and File.regular?(restore_file) do
      {:ok, restore_file}
    else
      {:error,
       Error.exception(
         reason: :invalid_restore_file,
         message: "Restore file is invalid or inaccessible",
         term: restore_file
       )}
    end
  end

  defp ensure_restore_file(other) do
    {:error,
     Error.exception(
       reason: :invalid_restore_file,
       message: "Restore file is invalid or inaccessible",
       term: other
     )}
  end

  # Ensures that the restore operation has been confirmed. Returns :ok if confirmed, otherwise an
  # error with a specific reason.
  defp ensure_restore_confirmed(_repo, _repo_config, %{confirm: true}) do
    :ok
  end

  defp ensure_restore_confirmed(repo, _repo_config, %{confirm: false}) do
    {:error,
     Error.exception(
       reason: :restore_not_confirmed,
       message: "Restore not confirmed",
       repo: repo
     )}
  end

  defp ensure_restore_confirmed(repo, _repo_config, %{confirm: prompt_fun})
       when is_function(prompt_fun, 0) do
    case prompt_fun.() do
      true ->
        :ok

      false ->
        {:error,
         Error.exception(
           reason: :restore_not_confirmed,
           message: "Restore not confirmed",
           repo: repo
         )}

      other ->
        {:error,
         Error.exception(
           reason: :invalid_confirm_function_result,
           message: "Invalid confirmation function result",
           repo: repo,
           term: other
         )}
    end
  end

  defp ensure_restore_confirmed(repo, _repo_config, %{confirm: {m, f, a}})
       when is_atom(m) and is_atom(f) and is_list(a) do
    case apply(m, f, a) do
      true ->
        :ok

      false ->
        {:error,
         Error.exception(
           reason: :restore_not_confirmed,
           message: "Restore not confirmed",
           repo: repo
         )}

      other ->
        {:error,
         Error.exception(
           reason: :invalid_confirm_function_result,
           message: "Invalid confirmation function result",
           repo: repo,
           term: other
         )}
    end
  end

  defp ensure_restore_confirmed(repo, _repo_config, _options) do
    {:error,
     Error.exception(
       reason: :missing_restore_confirmation,
       message: "Restore not confirmed (missing confirmation)",
       repo: repo
     )}
  end
end
