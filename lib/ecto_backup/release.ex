defmodule EctoBackup.Release do
  @moduledoc """
  Provides functions for running backup and restore operations in a release environment.

  This is similar to how the Mix tasks work in a development environment, but is designed to be
  used in a release where Mix is not available.

  You can use `mix ecto_backup.gen.release` to generate convenience scripts for performing backup
  and restore operations in a release. See `Mix.Tasks.EctoBackup.Gen.Release` for more details.

  These functions are intended to be run via the `eval` command in a release, for example:

      bin/my_app eval "EctoBackup.Release.backup(\\"-v\\")"
      bin/my_app eval "EctoBackup.Release.restore(\\"-r MyRepo -v /path/to/file.db\\")"

  Arguments should be a string and are parsed similarly to the Mix tasks, see
  `Mix.Tasks.EctoBackup.Backup` and `Mix.Tasks.EctoBackup.Restore` for more details on available
  options.
  """

  alias EctoBackup.CLI

  @doc """
  Performs backups of Ecto repositories in a release environment.

  Accepts a string of arguments similar to those accepted by the `Mix.Tasks.EctoBackup.Backup` mix
  task. They will be split with `OptionParser.split/1` and parsed exactly the same as the Mix
  task.
  """
  @spec backup(String.t()) :: :ok | {:error, term()}
  def backup(args \\ "") do
    Application.ensure_all_started([:ecto_backup, :ecto_sql, :telemetry])
    options = OptionParser.split(args) |> CLI.parse_backup_args!()
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
  rescue
    e ->
      CLI.fatal(e, 1)
  after
    CLI.detach()
  end

  @doc """
  Restores an Ecto repository from a backup file in a release environment.

  Accepts a string of arguments similar to those accepted by the `Mix.Tasks.EctoBackup.Restore` mix
  task. They will be split with `OptionParser.split/1` and parsed exactly the same as the Mix
  task.
  """
  @spec restore(String.t()) :: :ok | {:error, term()}
  def restore(args \\ "") do
    Application.ensure_all_started([:ecto_backup, :ecto_sql, :telemetry])
    options = OptionParser.split(args) |> CLI.parse_restore_args!()
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
  rescue
    e ->
      CLI.fatal(e, 1)
  after
    CLI.detach()
  end
end
