defmodule EctoBackup do
  @moduledoc """
  EctoBackup provides functionality to back up and restore Ecto repositories.

  ## Repo Discovery

  The functions in this module operate on one or more Ecto repositories. The list of repositories
  will default to those configured in the `:ecto_repos` application environment for your app,
  which is how you normally configure the list of Repos for Ecto tasks, such as `mix ecto.migrate`.

  You can instead provide an explicit list of repos to backup by setting the `:ecto_repos` option
  in the `:ecto_backup` application environment:

      config :ecto_backup, ecto_repos: [MyApp.Repo, MyApp.AnotherRepo]

  Or you can provide the list of repos in the `:repos` option of the backup function, see
  `backup/1`.

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
  `:password`, and `:hostname` are also needed. Other adapter-specific options may also be
  given, such as `:port`, `:socket`, or SSL options.

  Additionally, EctoBackup specific options can be set in the same way, such as:

    - `:backup_file` to specify exactly what file to write to
    - `:adapter` to specify which backup adapter to use instead of auto-detecting from the repo's
      adapter.

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

  alias EctoBackup.Adapter
  alias EctoBackup.Conf

  @doc """
  Initiates a backup for the specified repositories.

  Returns `{:ok, backup_file}` on success, where `backup_file` is the path to the created backup
  file, or `{:error, reason}` on failure.

  ## Options

    - `:repos` - A list of repositories to back up. If not provided, the default repositories
      from the application configuration will be used. See the
      [Repo Discovery](#module-repo-discovery) and
      [Individual Repo Configuration](#module-individual-repo-configuration) sections for more
      details.
    - `:backup_dir` - The directory where backup files will be stored if not individually
      specified. This directory must exist and be writable before calling this function.

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

  """

  def backup(opts \\ []) do
    options = Map.new(opts)
    {repo_specs, options} = Map.pop(options, :repos, [])

    with {:ok, repo_configs} <- Conf.get_repo_configs(repo_specs) do
      metadata = %{
        repos: repo_configs,
        options: options
      }

      :telemetry.span([:ecto_backup, :backup], metadata, fn ->
        results = Enum.map(repo_configs, &do_repo_backup(&1, options))
        {results, Map.put(metadata, :results, results)}
      end)
    end
  end

  defp do_repo_backup({repo, repo_config}, options) do
    with {:ok, backup_file} <- Conf.get_backup_file(repo_config, options) do
      metadata = %{
        repo: repo,
        repo_config: repo_config,
        backup_file: backup_file,
        options: options
      }

      :telemetry.span(
        [:ecto_backup, :backup, :repo],
        metadata,
        fn ->
          result = Adapter.backup(repo, repo_config, backup_file, options)
          {result, Map.put(metadata, :result, result)}
        end
      )
    end
  end
end
