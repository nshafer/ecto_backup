defmodule EctoBackup.CLI do
  @moduledoc """
  Command Line Interface (CLI) utilities for EctoBackup.
  """

  alias EctoBackup.CLI

  @type cmd_opts :: [
          {:cd, Path.t()}
          | {:on_output, (binary() -> term())}
          | {:into, Collectable.t() | nil}
          | {:lines, pos_integer()}
          | {:stderr_to_stdout, boolean()}
          | {:use_stdio, boolean()}
          | {:env, [{binary(), binary() | nil}]}
          | {:quiet, boolean()}
          | {atom(), term()}
        ]

  defstruct [:callback, :into]

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
        _ -> "** (#{mod}) Error"
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
  Parses command line arguments into an options map.

  This raises an error if invalid arguments are provided.
  """
  @spec parse_backup_args!([binary()]) :: map()
  def parse_backup_args!(args) do
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

    {opts, _} = OptionParser.parse!(args, strict: switches, aliases: aliases)

    %{
      repos: Keyword.get_values(opts, :repo) |> Enum.map(&Module.concat([&1])),
      backup_dir: opts[:backup_dir],
      verbose: opts[:verbose] || false,
      quiet: opts[:quiet] || false
    }
  end

  @doc """
  Converts command line options into backup options.
  """
  def backup_opts_from_cli_opts(cli_opts) do
    %{}
    |> maybe_put_option(:repos, Map.get(cli_opts, :repos), [])
    |> maybe_put_option(:backup_dir, Map.get(cli_opts, :backup_dir), nil)
  end

  defp maybe_put_option(opts, key, value, not_value)
  defp maybe_put_option(opts, _key, value, value), do: opts
  defp maybe_put_option(opts, key, value, _), do: Map.put(opts, key, value)

  @doc """
  Executes the given `command`.

  `command` is either a string, to be executed as a `System.shell/2` command, or a `{executable,
  args}` to be executed via `System.cmd/3`.

  ## Options

    * `:on_output` - a callback function that receives each chunk of output as it is produced. By
    default output is streamed without any packet lengths via `Port`, so the callback may receive
    several lines and/or partial lines. If you want line-by-line output, use the `:lines` option.
    This may be a tuple `{acc, fun}` where `fun` is called with the accumulator and each chunk of
    output as its two arguments, and must return the updated accumulator.

    * `:into` - an IO device or collectable to send output to, defaults to `""`. If `:on_output`
      is also provided, the callback is invoked before sending output to `:into`. If `:on_output`
      is set then this may be set to `nil` to avoid collecting output.

    * `:lines` - read output line-by-line, expects an integer number of lines to buffer internally
      (1024 is a reasonable default)

    * `:cd` - the directory to run the command in

    * `:stderr_to_stdout` - redirects stderr to stdout, defaults to `true`, unless `:use_stdio` is
      set to `false`

    * `:use_stdio` - controls whether the command should use `stdin` / `stdout` / `stderr`,
      defaults to `true`

    * `:env` - a list of environment variables, defaults to `[]`

    * `:quiet` - overrides the `on_output` callback to do nothing

  """
  @spec cmd(String.t() | {String.t(), [String.t()]}, cmd_opts) ::
          exit_status :: non_neg_integer
  def cmd(command, options \\ []) do
    callback =
      if options[:quiet] do
        fn x -> x end
      else
        options[:on_output]
      end

    use_stdio = Keyword.get(options, :use_stdio, true)
    into = Keyword.get(options, :into, "")

    options =
      options
      |> Keyword.take([:cd, :stderr_to_stdout, :env, :use_stdio, :lines])
      |> Keyword.put(:into, %EctoBackup.CLI{callback: callback, into: into})
      |> Keyword.put_new(:stderr_to_stdout, use_stdio)

    case command do
      {command, args} -> System.cmd(command, args, options)
      command when is_binary(command) -> System.shell(command, options)
    end
  end

  defimpl Collectable do
    def into(%EctoBackup.CLI{callback: nil, into: nil}) do
      raise ArgumentError, "must set `:callback` and/or `:into`"
    end

    def into(%EctoBackup.CLI{callback: nil, into: into}) do
      Collectable.into(into)
    end

    def into(%EctoBackup.CLI{callback: {acc, fun}, into: nil}) when is_function(fun) do
      fun = fn
        acc, {:cont, data} -> fun.(acc, data)
        _, _ -> :ok
      end

      {acc, fun}
    end

    def into(%EctoBackup.CLI{callback: fun, into: nil}) do
      fun = fn
        _, {:cont, data} -> fun.(data)
        _, _ -> :ok
      end

      {:ok, fun}
    end

    def into(%EctoBackup.CLI{callback: {cb_acc, cb_fun}, into: into}) when is_function(cb_fun) do
      {into_acc, into_fun} = Collectable.into(into)

      fun = fn
        {cb_acc, into_acc}, {:cont, data} ->
          {cb_fun.(cb_acc, data), into_fun.(into_acc, {:cont, data})}

        {_, into_acc}, :done ->
          into_fun.(into_acc, :done)

        {_, into_acc}, :halt ->
          into_fun.(into_acc, :halt)
      end

      {{cb_acc, into_acc}, fun}
    end

    def into(%EctoBackup.CLI{callback: cb_fun, into: into}) when is_function(cb_fun) do
      {into_acc, into_fun} = Collectable.into(into)

      fun = fn
        into_acc, {:cont, data} ->
          cb_fun.(data)
          into_fun.(into_acc, {:cont, data})

        into_acc, command ->
          into_fun.(into_acc, command)
      end

      {into_acc, fun}
    end
  end

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
            ": ",
            backup_file,
            "\n"
          ]

        {:error, repo, error} ->
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
      duration >= 60 * 60 * 1000 ->
        hours = div(duration, 60 * 60 * 1000)
        duration = rem(duration, 60 * 60 * 1000)
        minutes = div(duration, 60 * 1000)
        duration = rem(duration, 60 * 1000)
        seconds = Float.round(duration / 1000, 2)
        "#{hours}h #{minutes}m #{seconds}s"

      duration >= 60 * 1000 ->
        minutes = div(duration, 60 * 1000)
        duration = rem(duration, 60 * 1000)
        seconds = Float.round(duration / 1000, 2)
        "#{minutes}m #{seconds}s"

      duration >= 1000 ->
        seconds = Float.round(duration / 1000, 2)
        "#{seconds}s"

      true ->
        "#{duration}ms"
    end
  end
end
