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

  @type backup_result :: {:ok, String.t()} | {:error, term()}

  @doc """
  Initiates a backup of one or more Ecto repositories.

  This will attempt to validate the configuration first, and raise an `EctoBackup.ConfError` if
  any configuration issues are found. If all configuration is valid, it will attempt to back up
  each repository in turn, returning a list of results for each repo. If any repo backup fails,
  the overall operation will still attempt to continue to back up the remaining repos.

  Returns a list of results on success which is a list of tuples of `{:ok,
  repo, backup_file}` or `{:error, repo, reason}` for each repo backed up. Each `backup_file` is the
  path to the created backup.

  ## Options

    - `:repos` - A list of repositories to back up. If not provided, the default repositories from
      the application configuration will be used. See the [Repo Discovery](`backup/1#repo-discovery`)
      and [Individual Repo Configuration](`EctoBackup#module-individual-repo-configuration`) sections for more
      details.
    - `:backup_dir` - The directory where backup files will be stored if not individually
      specified. This directory must exist and be writable before calling this function. Can be a
      string, 2-arity function that takes the repo and repo_config and returns a string, or a MFA
      tuple to a function that takes args prepended with the repo and repo_config and returns a string.
    - Other options may be provided which will be passed to the adapter's backup function. See
      the documentation for the specific adapter being used for more details on supported options.

  ## Examples:

      # Backup default repos from application config
      EctoBackup.backup()

      # Backup specific repos
      EctoBackup.backup(repos: [MyApp.Repo, MyApp.AnotherRepo])

      # Backup with overridden options for a specific repo
      EctoBackup.backup(
        backup_dir: "/custom/backup/dir",
        repos: [
          MyApp.Repo,
          {MyApp.AnotherRepo, backup_file: "/tmp/export.db"},
          {MyApp.YetAnotherRepo, username: "readonly_user"},
        ]
      )

  ## Repo Discovery

  The functions in this module operate on one or more Ecto repositories. The list of repositories
  will default to those configured in the `:ecto_repos` application environment for your app,
  which is how you normally configure the list of Repos for Ecto tasks, such as `mix
  ecto.migrate`.

  You can instead provide an explicit list of repos to backup by setting the `:ecto_repos` option
  in the `:ecto_backup` application environment:

      config :ecto_backup, ecto_repos: [MyApp.Repo, MyApp.AnotherRepo]

  Or you can provide the list of repos in the `:repos` option of the backup function, see
  `backup/1`.

  ## Telemetry Events

  During backup and restore operations, the following telemetry events are emitted:

    - `[:ecto_backup, :backup, :start]` - Emitted at the start of a backup operation.
    - `[:ecto_backup, :backup, :stop]` - Emitted at the end of a backup operation, includes
      `:duration` in measurements and the `:result` in metadata.
    - `[:ecto_backup, :backup, :repo, :start]` - Emitted at the start of a repo-specific backup
      operation. Includes the `:repo`, `:repo_config`, and `:backup_file` in metadata.
    - `[:ecto_backup, :backup, :repo, :stop]` - Emitted at the end of a repo-specific backup
      operation. Includes the `:repo`, `:repo_config`, `:backup_file`, and `:result` in metadata.
  """

  @spec backup(keyword() | map()) :: {:ok, [backup_result()]} | {:error, term()}
  def backup(opts \\ %{}) do
    options = Map.new(opts)
    {repo_specs, options} = Map.pop(options, :repos, [])

    with(
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
end
