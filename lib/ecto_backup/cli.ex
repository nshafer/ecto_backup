defmodule EctoBackup.CLI do
  @moduledoc false

  @doc false
  @spec parse_args!([binary()]) :: map()
  def parse_args!(args) do
    switches = [
      repo: [:string, :keep],
      backup_dir: :string,
      verbose: :boolean,
      quiet: :boolean
    ]

    aliases = [
      r: :repo,
      d: :backup_dir,
      v: :verbose,
      q: :quiet
    ]

    {opts, _} = OptionParser.parse!(args, switches: switches, aliases: aliases)

    %{
      repos: Keyword.get_values(opts, :repo) |> Enum.map(&Module.concat([&1])),
      backup_dir: opts[:backup_dir],
      verbose: opts[:verbose] || false,
      quiet: opts[:quiet] || false
    }
  end

  def backup_opts_from_cli_opts(cli_opts) do
    %{}
    |> maybe_put_option(:repos, Map.get(cli_opts, :repos), [])
    |> maybe_put_option(:backup_dir, Map.get(cli_opts, :backup_dir), nil)
  end

  defp maybe_put_option(opts, key, value, not_value)
  defp maybe_put_option(opts, _key, value, value), do: opts
  defp maybe_put_option(opts, key, value, _), do: Map.put(opts, key, value)

  @doc """
  Formats a log message for terminal output using ANSI escape sequences.

  The log message includes a timestamp, log level, and the provided message. The log level is
  color-coded for better visibility in the terminal.

  This should be formatted with `IO.ANSI.format/1` before being printed to the terminal with
  `IO.puts/1`, as a newline is not included. This includes a carriage return and clear line ANSI
  code at the start to overwrite the current line, which is useful when printing log messages
  while a progress bar is being displayed.
  """
  def format_log(level, message) do
    level_color =
      case level do
        :info -> :default_color
        :warning -> :yellow
        :error -> :red
        _ -> :default_color
      end

    [
      [?\r, :clear_line],
      level_color,
      message
    ]
  end

  @doc """
  Formats a progress bar for terminal output using ANSI escape sequences.

  The progress bar includes the subject, a counter, a visual bar, and a percentage. The width of
  the progress bar is dynamically calculated based on the terminal width.

  This should be formatted with `IO.ANSI.format/1` before being printed to the terminal with
  `IO.write/1` and not `IO.puts/1`, to avoid adding newlines. This leaves the cursor in the last
  column of the terminal, so if anything prints after this, it should appear on a new line, but
  this is not guaranteed. If you desire to print anything to the screen, you should print a
  carriage return followed by a `:clear_line` ANSI code first so that the progress bar is erased.
  """
  def format_progress(subject, completed, total) do
    term_width = term_width()

    # Counter is "[15/36]" or "[45/145]"
    counter = "[#{completed}/#{total}]"

    # Percent is " 41%"
    percent = "#{trunc(completed / total * 100) |> to_string() |> String.pad_leading(4)}%"

    # Bar takes 35% of terminal width, minus 2 for the brackets
    # [##########----------------]
    bar_width = trunc(term_width * 0.35) - 2
    num_hashes = trunc(completed / total * bar_width)
    num_dashes = bar_width - num_hashes
    bar = "[#{String.duplicate("#", num_hashes)}#{String.duplicate("-", num_dashes)}]"

    # Subject takes the remaining space, minus spaces between elements
    subject_width = term_width - (byte_size(counter) + byte_size(percent) + byte_size(bar) + 4)
    subject = String.slice(subject, 0, subject_width) |> String.pad_trailing(subject_width)

    [?\r, :clear_line, :bright, subject, :reset, " ", counter, " ", bar, " ", percent, " "]
  end

  @doc """
  Formats a repository name for terminal output using ANSI escape sequences.
  """
  @spec format_repo(module()) :: [term()]
  def format_repo(repo) do
    [:cyan, inspect(repo), :default_color]
  end

  @doc """
  Formats a summary of backup or restore results for terminal output using ANSI escape sequences.
  """
  @spec format_results_summary([EctoBackup.backup_result()]) :: [[term()]]
  def format_results_summary(results) do
    for result <- results do
      case result do
        {:ok, repo, backup_file} ->
          [
            [:green, "✔", :default_color],
            " ",
            format_repo(repo),
            " ",
            backup_file,
            "\n"
          ]

        {:error, repo, error} ->
          [
            [:red, "✘", :default_color],
            " ",
            format_repo(repo),
            " ",
            Exception.message(error),
            "\n"
          ]
      end
    end
  end

  @doc """
  Returns the current local timestamp formatted as "HH:MM:SS.mmm".
  """
  @spec timestamp() :: String.t()
  def timestamp() do
    st = :erlang.system_time(:millisecond)
    {{_, _, _}, {h, m, s}} = :calendar.system_time_to_local_time(st, :millisecond)
    "#{pad_i(h, 2)}:#{pad_i(m, 2)}:#{pad_i(s, 2)}.#{rem(st, 1000) |> pad_i(3)}"
  end

  defp pad_i(int, width) do
    int
    |> Integer.to_string()
    |> String.pad_leading(width, "0")
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

  @doc """
  Returns a human-readable duration string given a duration and time_unit.
  """
  @spec duration(integer(), :native | :millisecond | :microsecond | :nanosecond) :: String.t()
  def duration(duration, time_unit \\ :native) do
    duration = System.convert_time_unit(duration, time_unit, :millisecond)

    cond do
      duration > 60 * 60 * 1000 ->
        "#{div(duration, 60 * 60 * 1000)}h " <>
          duration(rem(duration, 60 * 60 * 1000), :millisecond)

      duration > 60 * 1000 ->
        "#{div(duration, 60 * 1000)}m " <> duration(rem(duration, 60 * 1000), :millisecond)

      duration > 1000 ->
        "#{Float.round(duration / 1000, 2)}s"

      true ->
        "#{duration}ms"
    end
  end
end
