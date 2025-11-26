defmodule EctoBackup.CLI.Shell.IO do
  # The default shell for EctoBackup CLI interactions. This simply prints messages to standard
  # output and error, with support for a persistent status line if ANSI escape sequences are
  # enabled. If ANSI is not enabled, status messages are ignored.

  @moduledoc false

  @behaviour EctoBackup.CLI.Shell

  @doc """
  Prints the given ANSI message to the shell followed by a newline.
  """
  @impl true
  def info(message) do
    emit? = IO.ANSI.enabled?()

    message =
      message
      |> clear_line(emit?)
      |> IO.ANSI.format(emit?)

    IO.puts(message)
    reprint_status(emit?)

    :ok
  end

  @doc """
  Prints the given ANSI warning to the shell followed by a newline.
  """
  @impl true
  def warning(message) do
    emit? = IO.ANSI.enabled?()

    message =
      [:yellow, message]
      |> clear_line(emit?)
      |> IO.ANSI.format(emit?)

    IO.puts(message)
    reprint_status(emit?)

    :ok
  end

  @doc """
  Prints the given ANSI error to the shell followed by a newline.
  """
  @impl true
  def error(message) do
    emit? = IO.ANSI.enabled?()

    message =
      [:red, message]
      |> clear_line(emit?)
      |> IO.ANSI.format(emit?)

    IO.puts(:stderr, message)
    reprint_status(emit?)

    :ok
  end

  @doc """
  Prints the given ANSI status message to the current line of the shell if ANSI is enabled.

  Passing `nil` clears the status line.

  If ANSI is not enabled, this function does nothing.
  """
  @impl true
  def status(message) do
    emit? = IO.ANSI.enabled?()

    write_status(message, emit?)
    update_status(message)

    :ok
  end

  defp write_status(nil, true) do
    ""
    |> clear_line(true)
    |> IO.ANSI.format(true)
    |> IO.write()
  end

  defp write_status(nil, false) do
    :ok
  end

  defp write_status(message, true) do
    message
    |> clear_line(true)
    |> IO.ANSI.format(true)
    |> IO.write()
  end

  defp write_status(_message, false) do
    :ok
  end

  defp update_status(nil), do: EctoBackup.State.delete(:current_status)
  defp update_status(message), do: EctoBackup.State.put(:current_status, message)

  defp reprint_status(emit?) do
    case EctoBackup.State.fetch(:current_status) do
      {:ok, status} -> write_status(status, emit?)
      :error -> :ok
    end
  end

  defp clear_line(message, true) do
    # Only emit a carriage return if ANSI is enabled, as it is not removed by IO.ANSI.format/2
    [?\r, :clear_line, message]
  end

  defp clear_line(message, false) do
    message
  end
end
