defmodule Mix.Tasks.EctoBackup.Backup do
  @moduledoc """
  Mix task to perform backups of Ecto repositories.

  This task can back up one or more Ecto repositories configured in your application. This is
  typically configured in your "config/config.exs" or environment-specific configuration files.
  See the `EctoBackup` module documentation for more details on how repository backups are
  configured.

  ## Configuration Example

      # Configure defaults when running `mix ecto_backup.backup`
      config :ecto_backup,
        repos: [MyApp.Repo, MyApp.AnotherRepo],
        backup_dir: "/path/to/backup/dir"

      # For individual repo configuration, you can specify options like this:
      config :ecto_backup, MyApp.Repo,
        backup_file: {MyApp.Repo, :custom_backup_file, []},
        username: "backup_user"

  ## Command Line Options

    - `-r`, `--repo`       - Specify one or more Ecto repositories to back up. Can be used
      multiple times to back up multiple repos. If not specified, the default `:ecto_repos` from
      the application configuration will be used.
    - `-f`, `--file`       - Specify the file path for a specific repository to backup to. Can be
      used multiple times in conjunction with `--repo` to specify files for multiple repos. If not
      specified, the default backup file from the configuration or a generated filename will be
      used.
    - `-d`, `--backup-dir` - Specify the directory where backup files will be stored if not
      individually specified.
    - `-v`, `--verbose`    - Enable verbose logging output.
    - `-q`, `--quiet`      - Suppress all output except for warnings and errors.

  ## Examples

      # Back up all configured repos with default settings
      $ mix ecto_backup.backup

      # Back up all repos to a specific backup directory
      $ mix ecto_backup.backup --backup-dir /var/backups/custom_backup_dir

      # Back up a specific repo to a specified file
      $ mix ecto_backup.backup --repo MyApp.Repo --file /var/backups/my_app_repo_backup.db

      # Back up multiple repos with individual files
      $ mix ecto_backup.backup -r MyApp.Repo -f /var/backups/my_app_repo_backup.db \
                               -r MyApp.AnotherRepo -f /var/backups/another_repo_backup.db

  """
  @shortdoc "Performs backups of Ecto repositories"

  use Mix.Task
  alias EctoBackup.CLI

  @impl true
  def run(args) do
    Mix.Task.run("app.config", List.delete(args, "--force"))
    Application.ensure_all_started([:ecto_backup, :ecto_sql, :telemetry])

    options = CLI.parse_backup_args!(args)
    backup_opts = CLI.backup_opts_from_cli_opts(options)

    if options.quiet do
      CLI.shell(EctoBackup.CLI.Shell.Quiet)
    end

    CLI.attach(options)

    with {:ok, results} <- EctoBackup.backup(backup_opts) do
      CLI.summarize_backup_results(results)
      CLI.exit_if_errors(results, 1)
    else
      {:error, reason} -> CLI.fatal(reason, 1)
    end
  after
    CLI.detach()
  end
end
