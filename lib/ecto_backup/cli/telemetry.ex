defmodule EctoBackup.CLI.Telemetry do
  @moduledoc false

  alias EctoBackup.CLI

  def attach(opts) do
    result =
      :telemetry.attach_many(
        {__MODULE__, self()},
        [
          [:ecto_backup, :backup, :start],
          [:ecto_backup, :backup, :stop],
          [:ecto_backup, :backup, :repo, :start],
          [:ecto_backup, :backup, :repo, :stop],
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
        detach()
        attach(opts)
    end
  end

  def detach() do
    :telemetry.detach({__MODULE__, self()})
  end

  def handle_event([:ecto_backup, :backup, :start], _, metadata, _) do
    %{repos: repos} = metadata
    num_repos = length(repos)

    if num_repos > 1 do
      CLI.info([
        "Starting backups for #{num_repos} repositories:  ",
        repos
        |> Enum.map(fn {repo, _config} -> CLI.format_repo(repo) end)
        |> Enum.intersperse(", "),
        "\n"
      ])
    end
  end

  def handle_event([:ecto_backup, :backup, :stop], measurements, metadata, _) do
    %{duration: duration} = measurements
    %{repos: repos} = metadata
    num_repos = length(repos)

    CLI.reset_progress()

    if num_repos > 1 do
      CLI.info("All backups completed in #{CLI.duration(duration)}\n")
    end
  end

  def handle_event([:ecto_backup, :backup, :repo, :start], _, metadata, _) do
    %{repo: repo, repo_config: repo_config, backup_file: backup_file} = metadata

    padding = 15

    labels = [
      database: "Database",
      username: "Username",
      hostname: "Hostname",
      port: "Port",
      socket: "Socket",
      socket_dir: "Socket Dir"
    ]

    summary =
      Enum.map(labels, fn {key, label} ->
        case repo_config[key] do
          nil -> nil
          value -> [String.pad_trailing("  #{label}:", padding), "\"#{value}\"\n"]
        end
      end)
      |> Enum.reject(&is_nil/1)

    message =
      [
        "Starting backup at #{CLI.timestamp()}\n",
        summary,
        String.pad_trailing("  Backup File:", padding),
        "\"#{backup_file}\""
      ]

    CLI.info(repo, message)
  end

  def handle_event([:ecto_backup, :backup, :repo, :stop], measurements, metadata, _) do
    %{duration: duration} = measurements
    %{repo: repo} = metadata
    CLI.reset_progress()
    CLI.info(repo, ["Backup completed in ", CLI.duration(duration), "\n"])
  end

  def handle_event([:ecto_backup, :backup, :repo, :progress], measurements, metadata, _) do
    %{completed: completed, total: total} = measurements
    %{repo: repo} = metadata
    subject = metadata[:subject] || inspect(repo)
    label = metadata[:label]

    CLI.progress(subject, completed, total, label)
  end

  def handle_event([:ecto_backup, :backup, :repo, :message], _, metadata, opts) do
    %{repo: repo, level: level, message: message} = metadata

    cond do
      level == :info && opts.verbose -> CLI.info(repo, message)
      level == :warning -> CLI.warning(repo, ["Warning: ", message])
      level == :error -> CLI.error(repo, ["Error: ", message])
      true -> :ok
    end
  end
end
