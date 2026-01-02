defmodule EctoBackup.CLI do
  @moduledoc """
  Command Line Interface (CLI) utilities for EctoBackup.
  """

  alias EctoBackup.CLI

  @doc """
  Attaches a Command Line Interface.

  This sets up standard output for displaying progress and messages during backup and restore
  operations via telemetry events from `EctoBackup`.
  """
  def attach(opts) do
    CLI.Telemetry.attach(opts)
  end

  @doc """
  Detaches the Command Line Interface so that no further telemetry events are sent to the shell.
  """
  def detach() do
    CLI.Telemetry.detach()
  end

  @doc """
  Returns the current shell module used for input and output.
  """
  @spec shell() :: module()
  def shell() do
    EctoBackup.State.get(:shell, EctoBackup.CLI.Shell.IO)
  end

  @doc """
  Sets the shell module to be used for input and output.
  """
  @spec shell(module :: module()) :: :ok
  def shell(shell) do
    EctoBackup.State.put(:shell, shell)
  end

  @doc """
  Sends an informational message to the current shell.
  """
  def info(message), do: shell().info(message)

  @doc """
  Sends an informational message to the current shell, prefixed with the repository name.
  """
  def info(repo, message), do: shell().info(["[", format_repo(repo), "] ", message])

  @doc """
  Sends a warning message to the current shell.
  """
  def warning(message), do: shell().warning(message)

  @doc """
  Sends a warning message to the current shell, prefixed with the repository name.
  """
  def warning(repo, message), do: shell().warning(["[#{inspect(repo)}] ", message])

  @doc """
  Sends an error message to the current shell.
  """
  def error(message), do: shell().error(message)

  @doc """
  Sends an error message to the current shell, prefixed with the repository name.
  """
  def error(repo, message), do: shell().error(["[#{inspect(repo)}] ", message])

  @doc """
  Sends a fatal error message to the current shell and exits the program.
  """
  def fatal(message_or_exception, exit_status \\ 1)

  def fatal(message, exit_status) when is_binary(message) do
    fatal(EctoBackup.Error.exception(message), exit_status)
  end

  def fatal(%name{} = exception, exit_status) do
    mod = name |> Module.split() |> hd()

    label =
      case exception do
        %EctoBackup.ConfError{} -> "** (EctoBackup) Configuration error:"
        %EctoBackup.Error{} -> "** (EctoBackup) Fatal error:"
        _ -> "** (#{mod}) Error:"
      end

    error("#{label} #{Exception.message(exception)}")
    exit({:shutdown, exit_status})
  end

  @doc """
  Updates the progress status line in the current shell.
  """
  def progress(subject, completed, total, label, term_width \\ term_width()) do
    output = format_progress(subject, completed, total, label, term_width)
    shell().status(output)
  end

  @doc """
  Clears the progress status line in the current shell.
  """
  def reset_progress() do
    shell().status(nil)
  end

  @doc """
  Prints a summary of backup results to the current shell.
  """
  def summarize_backup_results(results) do
    if has_errors?(results) do
      error([
        if(shell() == EctoBackup.CLI.Shell.Quiet, do: "\n", else: ""),
        "Some backups completed with errors:\n",
        format_results_summary(results)
      ])
    else
      info([
        "Backup Summary:\n",
        format_results_summary(results)
      ])
    end
  end

  # Prints a summary of restore results to the current shell.
  def summarize_restore_results(results) do
    if has_errors?(results) do
      error([
        if(shell() == EctoBackup.CLI.Shell.Quiet, do: "\n", else: ""),
        "Some restores completed with errors:\n",
        format_results_summary(results)
      ])
    else
      info([
        "Restore Summary:\n",
        format_results_summary(results)
      ])
    end
  end

  defp format_results_summary(results) do
    for result <- results do
      format_result(result)
    end
  end

  defp format_result({:ok, repo, result}) do
    [
      [:green, "✔", :default_color],
      " ",
      format_repo(repo),
      ": ",
      result,
      "\n"
    ]
  end

  defp format_result({:error, repo, error}) do
    [
      [:red, "✘", :default_color],
      " ",
      format_repo(repo),
      ": ",
      :red,
      Exception.message(error),
      "\n"
    ]
  end

  @doc """
  Exits the program with the given exit status if there are any errors in the results.
  """
  def exit_if_errors(results, exit_status \\ 1) do
    if has_errors?(results) do
      exit({:shutdown, exit_status})
    end
  end

  defp has_errors?(results) do
    Enum.any?(results, fn
      {:error, _, _} -> true
      _ -> false
    end)
  end

  @doc """
  Parses command line arguments for backup into an options map.

  This raises an error if invalid arguments are provided.
  """
  @spec parse_backup_args!([binary()]) :: map()
  def parse_backup_args!(args) do
    switches = [
      repo: :keep,
      file: :keep,
      backup_dir: :string,
      verbose: :boolean,
      quiet: :boolean
    ]

    aliases = [
      r: :repo,
      f: :file,
      d: :backup_dir,
      v: :verbose,
      q: :quiet
    ]

    {opts, _} = OptionParser.parse!(args, strict: switches, aliases: aliases)

    %{
      repos: Keyword.get_values(opts, :repo) |> Enum.map(&Module.concat([&1])),
      files: Keyword.get_values(opts, :file),
      backup_dir: opts[:backup_dir],
      verbose: opts[:verbose] || false,
      quiet: opts[:quiet] || false
    }
  end

  @doc """
  Parses command line arguments for restore into an options map.

  This raises an error if invalid arguments are provided.
  """
  @spec parse_restore_args!([binary()]) :: map()
  def parse_restore_args!(args) do
    switches = [
      repo: :keep,
      file: :keep,
      restore_dir: :string,
      verbose: :boolean,
      quiet: :boolean,
      confirm: :keep
    ]

    aliases = [
      r: :repo,
      f: :file,
      d: :restore_dir,
      v: :verbose,
      q: :quiet
    ]

    {opts, _} = OptionParser.parse!(args, strict: switches, aliases: aliases)

    %{
      repos: Keyword.get_values(opts, :repo) |> Enum.map(&Module.concat([&1])),
      files: Keyword.get_values(opts, :file),
      restore_dir: opts[:restore_dir],
      verbose: opts[:verbose] || false,
      quiet: opts[:quiet] || false,
      confirm: Keyword.get_values(opts, :confirm) |> Enum.map(&Module.concat([&1]))
    }
  end

  @doc """
  Converts command line options into backup options.
  """
  def backup_opts_from_cli_opts(cli_opts) do
    %{}
    |> maybe_put_option(:repos, Map.get(cli_opts, :repos), [])
    |> maybe_put_option(:files, Map.get(cli_opts, :files), [])
    |> maybe_put_option(:backup_dir, Map.get(cli_opts, :backup_dir), nil)
  end

  def restore_opts_from_cli_opts(cli_opts) do
    %{}
    |> maybe_put_option(:repos, Map.get(cli_opts, :repos), [])
    |> maybe_put_option(:files, Map.get(cli_opts, :files), [])
    |> maybe_put_option(:restore_dir, Map.get(cli_opts, :restore_dir), nil)
    |> maybe_put_option(:confirm, Map.get(cli_opts, :confirm), [])
  end

  # Puts the given key and value into the opts map unless the value is equal to not_value.
  defp maybe_put_option(opts, key, value, not_value)
  defp maybe_put_option(opts, _key, value, value), do: opts
  defp maybe_put_option(opts, key, value, _), do: Map.put(opts, key, value)

  @doc """
  Formats a progress bar for terminal output using ANSI escape sequences.

  The progress bar includes the subject, a counter, a visual bar, and a percentage.
  """
  def format_progress(subject, completed, total, label, term_width) do
    # Counter is "15/36" or "45/145 MiB"
    counter = "#{completed}/#{total}#{if label, do: " #{label}", else: ""}"

    # Percent is " 41%"
    percent = "#{trunc(completed / total * 100) |> to_string() |> String.pad_leading(3)}%"

    # Bar takes 35% of terminal width, minus 2 for the brackets
    # [##########----------------]
    bar_width = trunc(term_width * 0.35) - 2
    num_hashes = trunc(completed / total * bar_width)
    num_dashes = bar_width - num_hashes
    bar = "[#{String.duplicate("#", num_hashes)}#{String.duplicate("-", num_dashes)}]"

    # Subject takes the remaining space, minus spaces between elements
    subject_width = term_width - (byte_size(counter) + byte_size(percent) + byte_size(bar) + 4)
    subject = String.slice(subject, 0, subject_width) |> String.pad_trailing(subject_width)

    [:bright, subject, :normal, " ", counter, " ", bar, " ", percent, " "]
  end

  @doc """
  Formats a repository name for terminal output using ANSI escape sequences.
  """
  @spec format_repo(module()) :: [term()]
  def format_repo(repo) do
    [:cyan, inspect(repo), :default_color]
  end

  @doc """
  Returns the width of the terminal in columns, 80 if it cannot be determined.
  """
  @spec term_width() :: integer()
  def term_width() do
    case :io.columns() do
      {:ok, width} -> width
      _ -> 80
    end
  end

  def confirm_restore(repo, repo_config) do
    prompt = [
      [:red, "DANGER! ", :default_color],
      "You are about to restore a backup for ",
      format_repo(repo),
      " from file:\n\n",
      [:yellow, "  #{repo_config[:restore_file]}\n\n", :default_color],
      "This operation will ",
      [:bright, "overwrite existing data ", :normal],
      "in the following database:\n\n",
      repo_config_summary(repo_config, 15),
      "\n",
      "Please type the name of the repository to confirm:"
    ]

    response =
      shell().prompt(prompt)
      |> String.trim()

    Module.concat([response]) == repo
  end

  @doc """
  Returns a summary of the repository configuration for display.
  """
  def repo_config_summary(repo_config, padding) do
    labels = [
      database: "Database",
      username: "Username",
      hostname: "Hostname",
      port: "Port",
      socket: "Socket",
      socket_dir: "Socket Dir"
    ]

    labels
    |> Enum.map(fn {key, label} ->
      case repo_config[key] do
        nil -> nil
        value -> [String.pad_trailing("  #{label}:", padding), "\"#{value}\"\n"]
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
