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
  for more information on the mix tasks.

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

    3. Options provided directly when invoking backup/restore functions. See `backup/1` for
       details.

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

  This will attempt to validate the configuration first, and return an error if any configuration
  issues are found. If all configuration is valid, it will attempt to back up each repository in
  turn via the appropriate adapter, returning a list of results for each repo. If any repo backup
  fails, the overall operation will still attempt to continue to back up the remaining repos.

  Returns `{:ok, list_of_results}` as long as any backups were attempted, but may contain errors
  in the results. Each result in the list will be either `{:ok, repo, backup_file}` or `{:error,
  repo, reason}` depending on whether that specific repo backup succeeded or failed.

  Returns `{:error, reason}` on any general errors that prevent backups from being attempted.

  ## Options

    * `:repos` - A list of repositories to back up. This may be a list of module names, or a list
      of `{repo, repo_options}` tuples to override options for specific repos. If not provided,
      the default repositories from the application configuration will be used. See the
      [Individual Repo Configuration](`EctoBackup#module-individual-repo-configuration`) section
      for more details.

    * `:backup_dir` - The directory where backup files will be stored if not individually
      specified. This directory must exist and be writable before calling this function. Can be a
      string, 2-arity function that takes the repo and repo_config and returns a string, or a MFA
      tuple to a function that takes args prepended with the repo and repo_config and returns a
      string.

    * Other options may be provided which will be passed to the adapter's backup function. See the
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

  ## Telemetry Events

  During backup and restore operations, the following telemetry events are emitted:

    * `[:ecto_backup, :backup, :start]` - Emitted at the start of a backup operation.

    * `[:ecto_backup, :backup, :stop]` - Emitted at the end of a backup operation, includes
      `:duration` in measurements and the `:result` in metadata.

    * `[:ecto_backup, :backup, :repo, :start]` - Emitted at the start of a repo-specific backup
      operation. Includes the `:repo`, `:repo_config`, and `:backup_file` in metadata.

    * `[:ecto_backup, :backup, :repo, :stop]` - Emitted at the end of a repo-specific backup
      operation. Includes the `:repo`, `:repo_config`, `:backup_file`, and `:result` in metadata.

  Additional telemetry events may be emitted by specific adapters during their operations.
  """

  @spec backup(keyword() | map()) :: {:ok, [backup_result()]} | {:error, term()}
  def backup(opts \\ %{}) do
    options = Map.new(opts)

    with(
      {:ok, repo_specs, options} <- Conf.get_repo_specs(options),
      {:ok, repo_configs} <- Conf.get_repo_configs(repo_specs),
      {:ok, backup_files} <- Conf.get_backup_files(repo_configs, options)
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
        try do
          case Adapter.backup(repo, repo_config, backup_file, options) do
            {:ok, file} -> {:ok, repo, file}
            {:error, error} -> {:error, repo, error}
          end
        rescue
          e ->
            {:error, repo, e}
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

    * `:repo` - The repository to restore. This option is required if more than one repository is
      configured in the application environment. This may be a module name or a `{repo,
      repo_options}` tuple. See the [Individual Repo
      Configuration](`EctoBackup#module-individual-repo-configuration`) section for more details.

    * `:confirm` - Must be set to `true` or a confirmation prompt function must be provided to
      confirm the restore operation. This is to prevent accidental restores which could lead to
      data loss. The confirmation prompt function should be a zero-arity function that returns
      `true` to confirm or `false` to cancel, or an MFA tuple to a function that returns `true` or
      `false`.

    * Other options may be provided which will be passed to the adapter's restore function. See
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

    * `[:ecto_backup, :restore, :start]` - Emitted at the start of a restore operation.

    * `[:ecto_backup, :restore, :stop]` - Emitted at the end of a restore operation, includes
      `:duration` in measurements and the `:result` in metadata.

    * `[:ecto_backup, :restore, :repo, :start]` - Emitted at the start of a repo-specific restore
      operation. Includes the `:repo`, `:repo_config`, and `:restore_file` in metadata.

    * `[:ecto_backup, :restore, :repo, :stop]` - Emitted at the end of a repo-specific restore
      operation. Includes the `:repo`, `:repo_config`, `:restore_file`, and `:result` in metadata.

  Additional telemetry events may be emitted by specific adapters during their operations.
  """
  def restore(restore_file, opts \\ %{}) do
    options = Map.new(opts)

    with(
      {:ok, repo_spec, options} <- get_repo_spec(options),
      {:ok, [{repo, repo_config}]} <- Conf.get_repo_configs([repo_spec]),
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
