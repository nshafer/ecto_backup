defmodule Mix.Tasks.EctoBackup.Backup do
  @moduledoc """
  Mix task to perform backups of Ecto repositories.
  """
  @shortdoc "Performs backups of Ecto repositories"

  # Process dictionary keys
  @pd_progress :ecto_backup_progress

  use Mix.Task
  import EctoBackup.CLI

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    options = parse_args!(args)
    backup_opts = backup_opts_from_cli_opts(options)

    if options.quiet do
      Mix.shell(Mix.Shell.Quiet)
    end

    attach_telemetry(options)

    with {:ok, results} <- EctoBackup.backup(backup_opts) do
      summarize_results(results)
    else
      {:error, %EctoBackup.ConfError{} = e} ->
        error("Configuration Error: #{Exception.message(e)}")

      {:error, e} when is_exception(e) ->
        error("Error: #{Exception.message(e)}")

      {:error, reason} ->
        error("Error: #{inspect(reason)}")
    end

    detach_telemetry()
  end

  defp summarize_results(results) do
    Mix.shell().info("Backup Summary:")
    Mix.shell().info(format_results_summary(results))
  end

  defp attach_telemetry(opts) do
    result =
      :telemetry.attach_many(
        "mix-ecto_backup.backup-handler",
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

    case result do
      :ok ->
        :ok

      {:error, :already_exists} ->
        detach_telemetry()
        attach_telemetry(opts)
    end
  end

  defp detach_telemetry() do
    :telemetry.detach("mix-ecto_backup.backup-handler")
  end

  def handle_event([:ecto_backup, :backup, :start], _, metadata, _) do
    %{repos: repos} = metadata
    num_repos = length(repos)

    if num_repos > 1 do
      info([
        "Starting backups for #{num_repos} repositories:  ",
        repos
        |> Enum.map(fn {repo, _config} -> format_repo(repo) end)
        |> Enum.intersperse(", "),
        :reset,
        "\n"
      ])
    end
  end

  def handle_event([:ecto_backup, :backup, :stop], measurements, metadata, _) do
    %{duration: duration} = measurements
    %{repos: repos} = metadata
    num_repos = length(repos)

    if num_repos > 1 do
      info("All backups completed in #{duration(duration)}\n")
    end
  end

  def handle_event([:ecto_backup, :backup, :repo, :start], _, metadata, _) do
    %{repo: repo, repo_config: repo_config, backup_file: backup_file} = metadata

    message =
      [
        "Starting backup at #{timestamp()}\n",
        "  Database:    \"#{repo_config[:database]}\"\n",
        if(repo_config[:username], do: "  Username:    \"#{repo_config[:username]}\"\n"),
        if(repo_config[:hostname], do: "  Hostname:    \"#{repo_config[:hostname]}\"\n"),
        if(repo_config[:port], do: "  Port:       \"#{repo_config[:port]}\"\n"),
        "  Backup File: \"#{backup_file}\"\n"
      ]

    info(["[", format_repo(repo), "] ", Enum.reject(message, &is_nil/1)])
  end

  def handle_event([:ecto_backup, :backup, :repo, :stop], measurements, metadata, _) do
    %{duration: duration} = measurements
    %{repo: repo} = metadata
    info(["[", format_repo(repo), "] Backup completed in ", duration(duration), "\n"])
  end

  def handle_event([:ecto_backup, :backup, :repo, :progress], measurements, metadata, _) do
    %{completed: completed, total: total} = measurements
    %{repo: repo} = metadata
    subject = metadata[:subject] || inspect(repo)
    label = metadata[:label]

    # Save the progress in the process dictionary to re-output after log messages
    Process.put(@pd_progress, {subject, completed, total, label})

    progress(subject, completed, total, label)
  end

  def handle_event([:ecto_backup, :backup, :repo, :message], _, metadata, config) do
    %{repo: repo, level: level, message: message} = metadata

    cond do
      level == :info && config.verbose -> info(["[", format_repo(repo), "] #{message}"])
      level == :warning -> warning(["[", format_repo(repo), "] #{message}"])
      level == :error -> error(["[", format_repo(repo), "] #{message}"])
      true -> :ok
    end

    # Re-output progress bar after log message
    case Process.get(@pd_progress) do
      {subject, completed, total, label} -> progress(subject, completed, total, label)
      nil -> :ok
    end
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    # Ignore unhandled events that adapters might emit
    :ok

    # warning([
    #   "Unhandled telemetry event: #{inspect(event)} ",
    #   "measurements: #{inspect(measurements)} ",
    #   "metadata: #{inspect(metadata)} ",
    #   "config: #{inspect(config)}"
    # ])
  end

  defp log(level, message) do
    output = format_log(level, message)
    Mix.shell().info(output)
  end

  defp info(message), do: log(:info, message)

  defp warning(message), do: Mix.shell().info("Warning: #{message}")

  defp error(message), do: Mix.shell().error(message)

  # Output progress bar only if Mix.shell() is Mix.Shell.IO, otherwise noop. This uses
  # IO.ANSI.format_fragment() and IO.write() to avoid adding newlines and ANSI resets.
  defp progress(subject, completed, total, label) do
    format_progress(subject, completed, total, label)
    |> write()
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
