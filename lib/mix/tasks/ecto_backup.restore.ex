defmodule Mix.Tasks.EctoBackup.Restore do
  @moduledoc """
  Mix task to restore an Ecto repository from a backup file.

  This task will restore a single Ecto repository from the specified backup file. The backup file
  to restore is required as the first and only argument to the task. If more than one repository
  is configured in the `:ecto_backup` application configuration, the repository to restore must be
  specified using the `-r` or `--repo` command line option.

  ## Command Line Options

    - `-r`, `--repo`       - Specify exactly one Ecto repository to restore. Required if more
      than one repo is configured in the `:ecto_backup` application configuration.
    - `-v`, `--verbose`    - Enable verbose logging output.
    - `-q`, `--quiet`      - Suppress all output except for warnings and errors.
  """
  @shortdoc "Restores Ecto repository from backup file"

  use Mix.Task
  alias EctoBackup.CLI

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    {options, restore_file} = CLI.parse_restore_args!(args)

    restore_opts =
      options
      |> CLI.restore_opts_from_cli_opts()
      |> Map.put_new(:confirm, {CLI, :confirm_restore, []})

    if options.quiet do
      CLI.shell(CLI.Shell.Quiet)
    end

    CLI.attach(options)

    with {:ok, repo} <- EctoBackup.restore(restore_file, restore_opts) do
      CLI.summarize_restore_result({:ok, repo})
    else
      {:error, reason} ->
        CLI.fatal(reason, 1)

      {:error, repo, error} ->
        CLI.summarize_restore_result({:error, repo, error})
        exit({:shutdown, 1})
    end
  after
    CLI.detach()
  end
end
