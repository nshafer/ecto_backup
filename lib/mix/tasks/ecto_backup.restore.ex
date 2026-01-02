defmodule Mix.Tasks.EctoBackup.Restore do
  @moduledoc """
  Mix task to perform restoration of Ecto repositories from backup files.

  This task can restore one or more Ecto repositories configured in your application. This is
  typically configured in your "config/config.exs" or environment-specific configuration files.
  See the `EctoBackup` module documentation for more details on how repository restores are
  configured

  ## Configuration Example

      # Configure defaults when running `mix ecto_backup.restore`
      # NOTE: backup_dir is use as the default restore_dir if not explicitly set
      config :ecto_backup,
        repos: [MyApp.Repo, MyApp.AnotherRepo],
        backup_dir: "/path/to/backup/dir"

      # For individual repo configuration, you can specify options like this:
      config :ecto_backup, MyApp.Repo,
        restore_dir: "/path/to/restore/dir",
        username: "restore_user"

  ## Command Line Options

    - `-r`, `--repo`       - Specify one or more Ecto repositories to restore. Can be used
      multiple times to restore multiple repos. If not specified, the default `:ecto_repos` from
      the application configuration will be used.
    - `-f`, `--file`       - Specify the file path to a backup file for a specific repository to
      restore from. Can be used multiple times in conjunction with `--repo` to specify files for
      multiple repos. If not specified, the default restore file from the configuration will be
      used, or the latest backup file found in the `:restore_dir` or `:backup_dir` that matches
      the default naming scheme will be used.
      - `--confirm`    - Skip confirmation prompts before performing restores. This must be given
      for each repo being restored as the full module name of the repo, e.g., `--confirm
      MyApp.Repo`. This is to prevent accidental restores.
    - `-d`, `--restore-dir` - Specify the directory where backup files will be restored from if
      not individually specified.
    - `-v`, `--verbose`    - Enable verbose logging output.
    - `-q`, `--quiet`      - Suppress all output except for warnings and errors.
  """
  @shortdoc "Performs restoration of Ecto repositories from backup files"

  use Mix.Task
  alias EctoBackup.CLI

  @impl true
  def run(args) do
    Mix.Task.run("app.config", List.delete(args, "--force"))
    Application.ensure_all_started([:ecto_backup, :ecto_sql, :telemetry])

    options = CLI.parse_restore_args!(args)
    restore_opts = CLI.restore_opts_from_cli_opts(options)
    restore_opts = Map.put_new(restore_opts, :confirm, {CLI, :confirm_restore, []})

    if options.quiet do
      CLI.shell(CLI.Shell.Quiet)
    end

    CLI.attach(options)

    with {:ok, results} <- EctoBackup.restore(restore_opts) do
      CLI.summarize_restore_results(results)
      CLI.exit_if_errors(results, 1)
    else
      {:error, reason} -> CLI.fatal(reason, 1)
    end
  after
    CLI.detach()
  end
end
