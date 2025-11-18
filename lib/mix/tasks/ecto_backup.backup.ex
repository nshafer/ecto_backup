defmodule Mix.Tasks.EctoBackup.Backup do
  @moduledoc """
  Mix task to perform backups of Ecto repositories.
  """
  @shortdoc "Performs backups of Ecto repositories"

  # Process dictionary keys
  @pd_progress :ecto_backup_progress

  use Mix.Task
  alias EctoBackup.CLI

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    options = CLI.parse_args!(args)
    backup_opts = CLI.backup_opts_from_cli_opts(options)

    if options.quiet do
      Mix.shell(Mix.Shell.Quiet)
    end

    attach_telemetry(options)

    with {:ok, results} <- EctoBackup.backup(backup_opts) do
      summarize_results(results)
    else
      {:error, %EctoBackup.ConfError{} = e} ->
        error("Configuration Error: #{Exception.message(e)}")

      {:error, %EctoBackup.Error{} = e} ->
        error("Error: #{Exception.message(e)}")

      {:error, e} when is_exception(e) ->
        error("Error: #{Exception.message(e)}")

      {:error, reason} ->
        error("Error: #{inspect(reason)}")
    end
  end

  defp summarize_results(results) do
    Mix.shell().info("\nBackup Summary:")
    Mix.shell().info(EctoBackup.CLI.format_results_summary(results))
  end

  defp attach_telemetry(opts) do
    :telemetry.attach_many(
      "sandbox-ecto-backup-handler",
      [
        [:ecto_backup, :backup, :start],
        [:ecto_backup, :backup, :stop],
        [:ecto_backup, :backup, :exception],
        [:ecto_backup, :backup, :repo, :start],
        [:ecto_backup, :backup, :repo, :stop],
        [:ecto_backup, :backup, :repo, :exception],
        [:ecto_backup, :backup, :repo, :progress],
        [:ecto_backup, :backup, :repo, :message]
      ],
      &__MODULE__.handle_event/4,
      opts
    )
  end

  def handle_event([:ecto_backup, :backup, :start], _measurements, metadata, _config) do
    %{repos: repos} = metadata

    if length(repos) > 1 do
      info([
        "Starting backups for #{length(repos)} repositories: ",
        Enum.map_join(repos, ", ", fn {repo, _config} -> inspect(repo) end)
      ])
    end
  end

  def handle_event([:ecto_backup, :backup, :stop], %{duration: duration}, metadata, _config) do
    %{repos: repos} = metadata

    if length(repos) > 1 do
      info("All backups completed in #{duration(duration)}")
    end
  end

  def handle_event([:ecto_backup, :backup, :repo, :start], _measurements, metadata, _config) do
    %{repo: repo, repo_config: repo_config, backup_file: backup_file} = metadata

    message =
      case repo_config do
        %{database: db} -> "Starting backup of database \"#{db}\" to \"#{backup_file}\""
        _ -> "Starting backup"
      end

    info("[#{inspect(repo)}] #{message}")
  end

  def handle_event(
        [:ecto_backup, :backup, :repo, :stop],
        %{duration: duration},
        %{repo: repo},
        _config
      ) do
    info("[#{inspect(repo)}] Backup completed in #{duration(duration)}")
  end

  def handle_event(
        [:ecto_backup, :backup, :repo, :progress],
        %{completed: completed, total: total},
        %{repo: repo},
        _config
      ) do
    # Save the progress in the process dictionary to re-output after log messages
    Process.put(@pd_progress, {completed, total})
    progress(inspect(repo), completed, total)
  end

  def handle_event(
        [:ecto_backup, :backup, :repo, :message],
        _measurements,
        %{repo: repo, level: level, message: message},
        config
      ) do
    cond do
      level == :info && config.verbose -> info("[#{inspect(repo)}] #{message}")
      level == :warning -> warning("[#{inspect(repo)}] #{message}")
      level == :error -> error("[#{inspect(repo)}] #{message}")
      true -> :ok
    end

    # Re-output progress bar after log message
    case Process.get(@pd_progress) do
      {completed, total} -> progress(inspect(repo), completed, total)
      nil -> :ok
    end
  end

  def handle_event(event, measurements, metadata, config) do
    warning([
      "Unhandled event: #{inspect(event)} ",
      "measurements: #{inspect(measurements)} ",
      "metadata: #{inspect(metadata)} ",
      "config: #{inspect(config)}"
    ])
  end

  defp log(level, message) do
    output = CLI.format_log(level, message)
    Mix.shell().info(output)
  end

  defp info(message), do: log(:info, message)

  defp warning(message), do: Mix.shell().info("Warning: #{message}")

  defp error(message), do: Mix.shell().error(message)

  # Output progress bar only if Mix.shell() is Mix.Shell.IO, otherwise noop. This uses
  # IO.ANSI.format_fragment() and IO.write() to avoid adding newlines and ANSI resets.
  defp progress(subject, completed, total) do
    CLI.format_progress(subject, completed, total)
    |> write()
  end

  defp duration(duration) do
    duration = System.convert_time_unit(duration, :native, :millisecond)

    cond do
      duration > 60_000 ->
        "#{Float.round(duration / 60000, 2)}min"

      duration > 1000 ->
        "#{Float.round(duration / 1000, 2)}s"

      true ->
        "#{duration}ms"
    end
  end

  # Write output without a newline, handling different Mix shells we care about
  defp write(message) do
    case Mix.shell() do
      Mix.Shell.IO -> IO.write(format(message))
      Mix.Shell.Process -> send(self(), {:mix_shell, :info, [format(message)]})
      _ -> :ok
    end
  end

  defp format(message) do
    case Mix.shell() do
      Mix.Shell.IO -> message |> IO.ANSI.format(true)
      Mix.Shell.Process -> message |> IO.ANSI.format(false) |> IO.iodata_to_binary()
      _ -> message
    end
  end
end
