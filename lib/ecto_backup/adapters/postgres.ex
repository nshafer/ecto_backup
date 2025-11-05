defmodule EctoBackup.Adapters.Postgres do
  @moduledoc """
  Adapter module implementing backup and restore for PostgreSQL databases.

  This will use `pg_dump` and `pg_restore` command line tools to perform the backup and restore
  operations, and so those utilities must be installed and available in the system's PATH. It is
  important to also note that this means the backup will be transferred to/from the database
  server, so plan accordingly for remote databases.

  The `pg_dump` and `pg_restore` commands will be configured to connect to the database using the
  provided repository configurations as explained in the
  [Individual Repo Configuration](#module-individual-repo-configuration)
  section of the main `EctoBackup` module documentation. Specifically:

  - `PGDATABASE` will be set from `:database`.
  - `PGHOST` will be set from `:socket`, `:socket_dir`, or `:hostname` in that order.
  - `PGOPTIONS` will be set from `:options` if provided.
  - `PGPORT` will be set from `:port`, defaulting to `5432` if not provided.
  - `PGUSER` will be set from `:username`.
  - Password will be provided via a securely created `.pgpass` file if `:password` is provided.

  Additional repo configuration options supported by this adapter:
    - `:pg_dump_cmd` - The command to use for `pg_dump`. Defaults to `"pg_dump"`.
    - `:pg_dump_args` - A list of arguments to pass to `pg_dump`. Defaults to
      `["--verbose", "--format=c", "--no-owner"]`.
    - `:pg_restore_cmd` - The command to use for `pg_restore`. Defaults to `"pg_restore"`.
    - `:pg_restore_args` - A list of arguments to pass to `pg_restore`. Defaults to
      `["--verbose", "--clean", "--no-owner", "--no-acl"]`.

  ## A note on default arguments
  - The `--verbose` argument is required for progress and feedback during backup and restore
    operations.
  - The `--format=c` argument for `pg_dump` creates a custom-format dump file, which is suitable
    for use with `pg_restore`.
  - The `--no-owner` argument prevents ownership information from being included in the dump,
    which can be useful when restoring to a different database or user.
  - The `--clean` argument for `pg_restore` ensures that existing database objects are dropped
    before being recreated from the dump.
  - The `--no-acl` argument prevents access control lists from being restored, which can help
    avoid permission issues during restore.

  ## Extra `:update` information:
  During backup and restore operations, additional data is provided in the update callbacks:

    - For `:started` updates, the `:table_count` key indicates the number of tables in the
      database being backed up or restored.
    - For `:progress` updates, the `:percent` key indicates the estimated completion percentage
      of the operation, based on the number of tables processed so far. Large tables may cause
      large jumps in percentage as they are completed.

  """

  @behaviour EctoBackup.Adapter

  import Ecto.Query, only: [from: 2]

  def backup(repo, repo_config, backup_file, options) do
    with(
      {:ok, cmd} <- pg_dump_cmd(repo_config),
      args <- pg_dump_args(repo_config, backup_file),
      env = pg_env(repo_config),
      table_count = get_table_count(repo)
    ) do
      EctoBackup.Adapter.call_update(:started, options, repo, %{
        repo_config: repo_config,
        table_count: table_count
      })

      case run_cmd(cmd, args, env, repo, table_count, options) do
        0 ->
          EctoBackup.Adapter.call_update(:completed, options, repo, %{result: {:ok, backup_file}})
          {:ok, backup_file}

        exit_status ->
          EctoBackup.Adapter.call_update(:completed, options, repo, %{
            result: {:error, {:exit_status, exit_status}}
          })

          {:error, {:exit_status, exit_status}}
      end
    end
  end

  # def restore(repo, repo_config, backup_file, options) do
  #   IO.puts("Starting PostgreSQL restore of #{repo.config()[:database]} from #{backup_file}...")
  #   dbg(repo_config)
  #   dbg(options)
  # end

  defp run_cmd(cmd, args, env, repo, table_count, options) do
    port =
      Port.open({:spawn_executable, cmd}, [
        :binary,
        :use_stdio,
        :stderr_to_stdout,
        :exit_status,
        {:args, args},
        {:env, port_env(env)},
        {:line, 1024}
      ])

    receive_output(port, repo, 0, table_count, options, [])
  end

  defp receive_output(port, repo, table_num, table_count, options, buffer) do
    receive do
      {^port, {:data, {:noeol, data}}} ->
        receive_output(port, repo, table_num, table_count, options, [data | buffer])

      {^port, {:data, {:eol, data}}} ->
        line = [data | buffer] |> Enum.reverse() |> IO.iodata_to_binary()

        level =
          cond do
            String.contains?(line, "error:") -> :error
            String.contains?(line, "warning:") -> :warning
            true -> :info
          end

        EctoBackup.Adapter.call_update(:message, options, repo, %{level: level, message: line})

        if String.starts_with?(line, "pg_dump: dumping contents of table") do
          percent = table_num / table_count
          EctoBackup.Adapter.call_update(:progress, options, repo, %{percent: percent})
          receive_output(port, repo, table_num + 1, table_count, options, [])
        else
          receive_output(port, repo, table_num, table_count, options, [])
        end

      {^port, {:exit_status, exit_status}} ->
        # Data may arrive after exit status in line mode
        receive do
          {^port, {:data, {_, data}}} ->
            line = [data | buffer] |> Enum.reverse() |> IO.iodata_to_binary()

            EctoBackup.Adapter.call_update(:message, options, repo, %{level: :info, message: line})

            exit_status
        after
          0 -> exit_status
        end
    end
  end

  defp get_table_count(repo) do
    query =
      from t in "pg_tables",
        where: t.schemaname != "information_schema" and not like(t.schemaname, "pg_%"),
        select: count(t.tablename)

    repo.one(query, log: false)
  end

  defp pg_dump_cmd(repo_config) do
    cmd = Map.get(repo_config, :pg_dump_cmd, "pg_dump")

    case System.find_executable(cmd) do
      nil -> {:error, :pg_dump_not_found}
      cmd -> {:ok, cmd}
    end
  end

  defp pg_dump_args(repo_config, backup_file) do
    args = Map.get(repo_config, :pg_dump_args, ["--verbose", "--format=c", "--no-owner"])

    if Enum.any?(args, fn arg -> arg in ["-f", "--file"] end) do
      {:error, :pg_dump_args_cannot_include_file_arg}
    else
      args ++ ["--file", backup_file]
    end
  end

  defp pg_env(repo_config) do
    # TODO: Handle password via .pgpass file and set PGPASSFILE env var
    %{
      "PGHOST" => repo_config[:socket] || repo_config[:socket_dir] || repo_config[:hostname],
      "PGPORT" => repo_config[:port] || "5432",
      "PGUSER" => repo_config[:username],
      "PGPASSWORD" => repo_config[:password],
      "PGDATABASE" => repo_config[:database]
    }
  end

  defp port_env(env) do
    Enum.map(env, fn
      {k, nil} -> {to_charlist(k), false}
      {k, v} -> {to_charlist(k), to_charlist(v)}
      other -> raise ArgumentError, "Invalid env key-value: #{inspect(other)}"
    end)
  end

  def valid_backup_file?(backup_file, expected_tables, opts \\ []) do
    with(
      true <- is_binary(backup_file),
      true <- File.exists?(backup_file),
      {:ok, %File.Stat{size: size}} <- File.stat(backup_file),
      true <- size > 0,
      tables <- list_backup_file_tables(backup_file, opts)
    ) do
      Enum.all?(expected_tables, &(&1 in tables))
    else
      _ -> false
    end
  end

  def list_backup_file_tables(backup_file, opts) do
    cmd = Keyword.get(opts, :pg_restore_cmd, "pg_restore")
    {output, 0} = System.cmd(cmd, ["--list", backup_file])

    output
    |> String.split("\n")
    |> Enum.map(fn line ->
      case Regex.run(~r/^\d+;\s+(?:\d+\s+)?\d+\s+TABLE\s(?:(\S+)\s)?(\S+)\s(\S+)$/, line) do
        [_full, _schema, table, _owner] -> table
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
