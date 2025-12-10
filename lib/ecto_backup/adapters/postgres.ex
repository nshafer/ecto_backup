defmodule EctoBackup.Adapters.Postgres do
  @moduledoc """
  Adapter module implementing backup and restore for PostgreSQL databases.

  This will use `pg_dump` and `pg_restore` command line tools to perform the backup and restore
  operations, and so those utilities must be installed and available in the system's `$PATH`. It
  is important to also note that this means that backups will be transferred from the database
  server to the local machine, and restores will be transferred from the local machine to the
  database server, so plan accordingly for remote databases.

  The `pg_dump` and `pg_restore` commands will be configured to connect to the database using the
  provided repository configurations as explained in the [Individual Repo
  Configuration](#module-individual-repo-configuration) section of the main `EctoBackup` module
  documentation. Specifically:

    - `PGDATABASE` will be set from `:database`.
    - `PGHOST` will be set from `:socket`, `:socket_dir`, or `:hostname` in that order.
    - `PGOPTIONS` will be set from `:options` if provided.
    - `PGPORT` will be set from `:port`, defaulting to `5432` if not provided.
    - `PGUSER` will be set from `:username`.
    - Password will be provided via a securely created `.pgpass` file if `:password` is provided.

  Additional repo configuration options supported by this adapter:

    - `:pg_dump_cmd` - The command to use for `pg_dump`. Defaults to `"pg_dump"`.
    - `:pg_dump_args` - A list of arguments to pass to `pg_dump`. Defaults to `["--verbose",
      "--format=c", "--no-owner"]`. See the note below on default arguments.
    - `:pg_restore_cmd` - The command to use for `pg_restore`. Defaults to `"pg_restore"`.
    - `:pg_restore_args` - A list of arguments to pass to `pg_restore`. Defaults to `["--verbose",
      "--clean", "--no-owner", "--no-acl"]`. See the note below on default arguments.

  ## A note on default arguments
    - The `--verbose` argument is required for progress and feedback during backup and restore
      operations.
    - The `--format=c` argument for `pg_dump` creates a custom-format dump file, which is the most
      flexible format, and compressed by default.
    - The `--no-owner` argument prevents ownership information from being included in the dump,
      which can be useful when restoring to a different database or user.
    - The `--clean` argument for `pg_restore` ensures that existing database objects are dropped
      before being recreated from the dump.
    - The `--no-acl` argument prevents access control lists from being restored, which can help
      avoid permission issues during restore.

  ## Telemetry Events
  During backup and restore operations, the following telemetry events are emitted:

    - `[:ecto_backup, :backup, :repo, :progress]` - Emitted periodically during backup to report
      progress. Due to how `pg_dump` works, this is emitted when dumping each table. Progress may
      appear to stall for large tables. Measurements include `:completed`, `:total`, and
      `:percent`. Metadata includes `:repo` and `:subject` (table name if applicable).
    - `[:ecto_backup, :backup, :repo, :message]` - Emitted for informational, warning, or error
      messages from the backup process. Metadata includes `:repo`, `:level` and `:message`.

  All telemetry events include the `:repo` in their metadata for context.
  """

  @behaviour EctoBackup.Adapter

  import Ecto.Query, only: [from: 2]
  alias EctoBackup.CLI
  alias EctoBackup.Conf
  alias EctoBackup.Error

  @impl true
  def backup(repo, repo_config, backup_file, options) do
    with(
      {:ok, cmd} <- pg_dump_cmd(repo, repo_config, options),
      {:ok, args} <- pg_dump_args(repo, repo_config, backup_file, options),
      {:ok, env} <- pg_env(repo, repo_config),
      {:ok, env} <- create_pgpass_file(repo, env, repo_config),
      {:ok, table_count} <- get_table_count(repo)
    ) do
      cmd_opts = [
        env: env,
        lines: 1024,
        on_output: on_backup_output_fun(repo, table_count)
      ]

      try do
        case CLI.cmd({cmd, args}, cmd_opts) do
          {_, 0} ->
            {:ok, backup_file}

          {output, exit_status} ->
            {:error,
             Error.exception(
               reason: :pg_dump_failed,
               message: "pg_dump failed with exit status #{exit_status}",
               term: {output, exit_status},
               repo: repo
             )}
        end
      after
        cleanup_pgpass_file(env)
      end
    end
  end

  @impl true
  def restore(repo, repo_config, restore_file, options) do
    with(
      {:ok, cmd} <- pg_restore_cmd(repo, repo_config, options),
      {:ok, args} <- pg_restore_args(repo, repo_config, restore_file, options),
      {:ok, env} <- pg_env(repo, repo_config),
      {:ok, env} <- create_pgpass_file(repo, env, repo_config),
      {:ok, tables} <- list_backup_file_tables(restore_file, pg_restore_cmd: cmd)
    ) do
      cmd_opts = [
        env: env,
        lines: 1024,
        on_output: on_restore_output_fun(repo, length(tables))
      ]

      try do
        case CLI.cmd({cmd, args}, cmd_opts) do
          {_, 0} ->
            :ok

          {output, exit_status} ->
            {:error,
             Error.exception(
               reason: :pg_restore_failed,
               message: "pg_restore failed with exit status #{exit_status}",
               term: {output, exit_status},
               repo: repo
             )}
        end
      after
        cleanup_pgpass_file(env)
      end
    end
  end

  defp pg_dump_cmd(repo, repo_config, options) do
    cmd = Conf.get(repo_config, options, :pg_dump_cmd, "pg_dump")

    case System.find_executable(cmd) do
      nil ->
        {:error,
         Error.exception(
           reason: :pg_dump_cmd_not_found,
           message: "pg_dump command #{inspect(cmd)} not found in system PATH",
           term: cmd,
           repo: repo
         )}

      cmd ->
        {:ok, cmd}
    end
  end

  defp pg_restore_cmd(repo, repo_config, options) do
    cmd = Conf.get(repo_config, options, :pg_restore_cmd, "pg_restore")

    case System.find_executable(cmd) do
      nil ->
        {:error,
         Error.exception(
           reason: :pg_restore_cmd_not_found,
           message: "pg_restore command #{inspect(cmd)} not found in system PATH",
           term: cmd,
           repo: repo
         )}

      cmd ->
        {:ok, cmd}
    end
  end

  defp pg_dump_args(repo, repo_config, backup_file, options) do
    default_args = ["--verbose", "--format=c", "--no-owner"]
    args = Conf.get(repo_config, options, :pg_dump_args, default_args)

    if Enum.any?(args, fn arg -> arg in ["-f", "--file"] end) do
      {:error,
       Error.exception(
         reason: :pg_dump_args_invalid,
         message: "pg_dump_args cannot contain -f or --file argument",
         repo: repo
       )}
    else
      # Always add `--no-password` to avoid password prompt
      {:ok, args ++ ["--no-password", "--file", backup_file]}
    end
  end

  defp pg_restore_args(repo, repo_config, restore_file, options) do
    default_args = ["--verbose", "--clean", "--no-owner", "--no-acl"]
    args = Conf.get(repo_config, options, :pg_restore_args, default_args)

    if Enum.any?(args, fn arg -> arg in ["-d", "--dbname"] end) do
      {:error,
       Error.exception(
         reason: :pg_restore_args_invalid,
         message: "pg_restore_args cannot contain -d or --dbname argument",
         repo: repo
       )}
    else
      # Always add `--no-password` to avoid password prompt
      {:ok, args ++ ["--no-password", "--dbname", repo_config[:database], restore_file]}
    end
  end

  defp pg_env(repo, repo_config) do
    if is_binary(repo_config[:database]) and repo_config[:database] != "" do
      {:ok,
       %{
         "PGDATABASE" => repo_config[:database],
         "PGHOST" => repo_config[:socket] || repo_config[:socket_dir] || repo_config[:hostname],
         "PGPORT" => repo_config[:port] || "5432",
         "PGUSER" => repo_config[:username],
         "PGOPTIONS" => repo_config[:options] || nil
       }}
    else
      {:error,
       Error.exception(
         reason: :database_not_specified,
         message: ":database is not specified in repo config",
         repo: repo
       )}
    end
  end

  defp create_pgpass_file(repo, env, repo_config) do
    case repo_config[:password] do
      nil ->
        {:ok, env}

      "" ->
        {:ok, env}

      password when is_binary(password) ->
        do_create_pgpass_file(password, env)

      _ ->
        {:error,
         Error.exception(
           reason: :invalid_password_value,
           message: ":password must be a string if provided",
           repo: repo
         )}
    end
  end

  defp do_create_pgpass_file(password, env) do
    with(
      {:ok, _pid} <- Temp.track(),
      {:ok, file, pgpass_path} <- Temp.open("ecto_backup_pgpass"),
      :ok <- IO.write(file, "*:*:*:*:#{password}\n"),
      :ok <- File.close(file),
      :ok <- File.chmod(pgpass_path, 0o600)
    ) do
      {:ok, Map.put(env, "PGPASSFILE", pgpass_path)}
    end
  end

  defp cleanup_pgpass_file(%{"PGPASSFILE" => pgpass_path} = _env) do
    File.rm_rf(pgpass_path)
  end

  defp cleanup_pgpass_file(_env), do: :ok

  defp get_table_count(repo) do
    fun = fn repo ->
      query =
        from t in "pg_tables",
          where: t.schemaname != "information_schema" and not like(t.schemaname, "pg_%"),
          select: count(t.tablename)

      repo.one(query, log: false)
    end

    case Ecto.Migrator.with_repo(repo, fun) do
      {:ok, ret, _} -> {:ok, ret}
      {:error, _} -> {:ok, nil}
    end
  end

  defp on_backup_output_fun(repo, total) do
    fun = fn completed, line ->
      emit_message_event(:backup, repo, line)

      if total && String.starts_with?(line, "pg_dump: dumping contents of table") do
        case Regex.run(~r/pg_dump: dumping contents of table "([^"]+)"/, line) do
          [_full, table_name] ->
            emit_progress_event(:backup, repo, completed, total, trim_table_name(table_name))

          _ ->
            emit_progress_event(:backup, repo, completed, total, nil)
        end

        completed + 1
      else
        completed
      end
    end

    {0, fun}
  end

  defp on_restore_output_fun(repo, total) do
    fun = fn completed, line ->
      emit_message_event(:restore, repo, line)

      if total && String.starts_with?(line, "pg_restore: processing data for table") do
        case Regex.run(~r/processing data for table "([^"]+)"/, line) do
          [_full, table_name] ->
            emit_progress_event(:restore, repo, completed, total, trim_table_name(table_name))

          _ ->
            emit_progress_event(:restore, repo, completed, total, nil)
        end

        completed + 1
      else
        completed
      end
    end

    {0, fun}
  end

  defp emit_progress_event(op, repo, completed, total, table_name) do
    measurements = %{
      completed: completed,
      total: total
    }

    metadata = %{
      repo: repo,
      subject: table_name && "Table: #{table_name}"
    }

    :telemetry.execute([:ecto_backup, op, :repo, :progress], measurements, metadata)
  end

  defp emit_message_event(op, repo, message) do
    level =
      cond do
        String.contains?(message, "error:") -> :error
        String.contains?(message, "warning:") -> :warning
        true -> :info
      end

    metadata = %{
      repo: repo,
      level: level,
      message: message
    }

    :telemetry.execute([:ecto_backup, op, :repo, :message], %{}, metadata)
  end

  defp trim_table_name(table_name) do
    table_name
    |> String.trim()
    |> String.trim("\"")
    |> String.trim_leading("public.")
  end

  @doc """
  Check if the given backup file is a valid PostgreSQL backup file and contains the expected
  tables.

  Uses `list_backup_file_tables/2` for listing tables in the backup file. Any extra tables in
  the backup file beyond the expected ones are ignored.
  """
  def valid_backup_file?(backup_file, expected_tables, opts \\ []) do
    with(
      true <- is_binary(backup_file),
      true <- File.exists?(backup_file),
      {:ok, %File.Stat{size: size}} <- File.stat(backup_file),
      true <- size > 0,
      {:ok, tables} <- list_backup_file_tables(backup_file, opts)
    ) do
      Enum.all?(expected_tables, &(&1 in tables))
    else
      _ -> false
    end
  end

  @doc """
  List the tables contained in the given PostgreSQL backup file.

  This is done by invoking `pg_restore --list` and parsing its output.

  ## Options

    - `:pg_restore_cmd` - The command to use for `pg_restore`. Defaults to `"pg_restore"` in
      the system path.
  """
  def list_backup_file_tables(backup_file, opts \\ []) do
    cmd = Keyword.get(opts, :pg_restore_cmd, "pg_restore")

    case CLI.cmd({cmd, ["--list", backup_file]}) do
      {output, 0} ->
        tables =
          output
          |> String.split("\n")
          |> Enum.map(fn line ->
            case Regex.run(~r/^\d+;\s+(?:\d+\s+)?\d+\s+TABLE\s(?:(\S+)\s)?(\S+)\s(\S+)$/, line) do
              [_full, _schema, table, _owner] -> table
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, tables}

      {output, exit_status} ->
        {:error,
         Error.exception(
           reason: :pg_restore_list_failed,
           message:
             "could not list tables in backup file #{backup_file}: #{exit_status}: #{output}",
           term: exit_status
         )}
    end
  end
end
