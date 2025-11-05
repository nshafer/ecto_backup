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

  ## Update Callback

  The `:update` option to the backup and restore functions allows you to provide a function that
  will be called with updates during the backup or restore process. This can be useful for logging
  messages, showing progress, updating a user interface, etc. Either a function with arity 3 can
  be provided, or an MFA tuple in the form `{Module, :function, [:args]}`, where the following
  arguments will be prepended to any that are provided.

  The function should accept three arguments:
    - `type` - An atom representing the type of update: `:started`, `:message`, `:progress`,
      `:completed`.
    - `repo` - The repository module currently being backed up.
    - `data` - A map containing additional information about the update. The contents of this map
      will vary depending on the `type` of update.

  ### Data for type `:started`

  This is called when the backup process for a repo starts. Keys:

  - `:repo_config` - The final configuration used for the repo backup. Care should be taken to
    avoid printing sensitive information such as passwords.

  Example:

      %{
        repo_config: %{
          database: "mydb",
          username: "backup_user",
          password: "supersecretpassword",
          backup_file: "/tmp/export.db",
          ...
        }
      }

  ### Data for type `:message`

  A message generated during the backup process, often from the underlying backup tool. Keys:
    - `:level` - An atom indicating the message level, such as `:info`, `:warning`, or `:error`.
    - `:message` - A string containing the message content.

  Example:

      %{
        level: :info,
        message: "Backing up table public.users"
      }

  ### Data for type `:progress`

  An update of the overall backup process. Not all adapters may support progress updates, and
  there is no guarantee they will start with 0.0 or end with 1.0. Keys:
    - `:percent` - A float between `0.0` and `1.0` indicating the progress percentage.

  Example:

      %{percent: 0.24}

  ### Data for type `:finished`

  The result of the backup operation. Keys:
    - `:result` - The result of the backup operation, which will be either `{:ok, backup_file}`
                  or `{:error, reason}`.

  Examples:

      %{result: {:ok, "/tmp/export.db"}}
      %{result: {:error, :timeout}}

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
    - `:update` - A function or MFA tuple that will be called with information updates during the
      backup process. See [Update Callback](#module-update-callback) section above.

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

      # Provide a function to receive updates during the backup process
      update_fn = fn
        :started, repo, %{repo_config: repo_config} ->
          IO.puts("Starting backup for \#{inspect(repo)}: \#{inspect(repo_config)}")
        :message, repo, %{level: level, message: message} ->
          IO.puts("[\#{level}] \#{inspect(repo)}: \#{message}")
        :progress, repo, %{percent: percent} ->
          IO.puts("Progress for \#{inspect(repo)}: \#{Float.round(percent * 100, 2)}%")
        :completed, repo, %{result: %{:ok, backup_file}} ->
          IO.puts("Completed backup for \#{inspect(repo)} to \#{inspect(backup_file)}")
        :completed, repo, %{result: {:error, reason}} ->
          IO.puts("Backup failed for \#{inspect(repo)}: \#{inspect(reason)}")
      end

      EctoBackup.backup(update: update_fn)

  """

  def backup(opts \\ []) do
    options = Map.new(opts)
    {repos, options} = Map.pop(options, :repos, [])

    with {:ok, repo_configs} <- Conf.get_repo_configs(repos) do
      for {repo, repo_config} <- repo_configs do
        with {:ok, backup_file} <- Conf.get_backup_file(repo_config, options) do
          Adapter.backup(repo, repo_config, backup_file, options)
        end
      end
    end
  end
end
