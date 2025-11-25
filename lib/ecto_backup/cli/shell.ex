defmodule EctoBackup.CLI.Shell do
  # This is very similar to `Mix.Shell` but tailored for EctoBackup's needs, such as including
  # support for a persistent status line, which is maintained across other output via ANSI control
  # sequences, where available. It is also available in release environments, unlike Mix.

  @moduledoc false

  @doc """
  Prints the given ANSI message to the shell.
  """
  @callback info(message :: IO.ANSI.ansidata()) :: :ok

  @doc """
  Prints the given ANSI warning to the shell.
  """
  @callback warning(message :: IO.ANSI.ansidata()) :: :ok

  @doc """
  Prints the given ANSI error to the shell.
  """
  @callback error(message :: IO.ANSI.ansidata()) :: :ok

  @doc """
  Prints the given ANSI status message to the current line of the shell.

  This is intended for displaying progress updates on a single line, overwriting
  previous status messages.

  Subsequent calls to `info/1`, `warning/1`, or `error/1` should re-print the status line
  after their output.

  Passing `nil` as the message should clear the status line.
  """
  @callback status(message :: IO.ANSI.ansidata() | nil) :: :ok
end
