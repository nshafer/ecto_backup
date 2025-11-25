defmodule Mix.Tasks.EctoBackup.Backup do
  @moduledoc """
  Mix task to perform backups of Ecto repositories.

  This task can back up one or more Ecto repositories configured in your application. This is
  typically configured in your "config/config.exs" or environment-specific configuration files.
  See the `EctoBackup` module documentation for more details on how repositories are configured.

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
      multiple times to back up multiple repos. If not specified, the default repos from the
      application configuration will be used.
    - `-d`, `--backup-dir` - Specify the directory where backup files will be stored if not
      individually specified.
    - `-v`, `--verbose`    - Enable verbose logging output.
    - `-q`, `--quiet`      - Suppress all output except for errors.
  """
  @shortdoc "Performs backups of Ecto repositories"

  use Mix.Task
  alias EctoBackup.CLI

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    options = CLI.parse_backup_args!(args)
    backup_opts = CLI.backup_opts_from_cli_opts(options)

    if options.quiet do
      EctoBackup.CLI.shell(EctoBackup.CLI.Shell.Quiet)
    end

    CLI.attach(options)

    with {:ok, results} <- EctoBackup.backup(backup_opts) do
      CLI.summarize_results(results)
    else
      {:error, %EctoBackup.ConfError{} = e} ->
        CLI.error("Configuration Error: #{Exception.message(e)}")

      {:error, e} when is_exception(e) ->
        CLI.error("Error: #{Exception.message(e)}")

      {:error, reason} ->
        CLI.error("Error: #{inspect(reason)}")
    end
  after
    CLI.detach()
  end
end
