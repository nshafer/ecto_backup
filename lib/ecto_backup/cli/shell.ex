defmodule EctoBackup.CLI.Shell do
  @moduledoc """
  A shell implementation for EctoBackup CLI interactions.

  This is very similar to `Mix.Shell` but tailored for EctoBackup's needs, such as including
  support for a persistent status line, which is maintained across other output via ANSI control
  sequences, where available. It is also available in release environments, unlike Mix.
  """
  @type cmd_opts :: [
          {:stderr_to_stdout, boolean()}
          | {:quiet, boolean()}
          | {:env, [{String.t(), String.t()}]}
          | {:cd, String.t()}
          | {atom(), term()}
        ]

  @doc """
  Print the given ANSI message to the shell.
  """
  @callback info(message :: IO.ANSI.ansidata()) :: :ok

  @doc """
  Print the given ANSI warning to the shell.
  """
  @callback warning(message :: IO.ANSI.ansidata()) :: :ok

  @doc """
  Print the given ANSI error to the shell.
  """
  @callback error(message :: IO.ANSI.ansidata()) :: :ok

  @doc """
  Print the given ANSI status message to the current line of the shell.

  This is intended for displaying progress updates on a single line, overwriting
  previous status messages.

  Subsequent calls to `info/1`, `warning/1`, or `error/1` should re-print the status line
  after their output.

  Passing `nil` as the message should clear the status line.
  """
  @callback status(message :: IO.ANSI.ansidata() | nil) :: :ok

  @doc """
  Prompts the user for input.
  """
  @callback prompt(message :: IO.ANSI.ansidata()) :: binary()

  @doc """
  Executes the given command and returns its exit status.

  Shortcut for `c:cmd/2` with empty options.
  """
  @callback cmd(command :: String.t()) :: integer

  @doc """
  Executes the given command and returns its exit status.

  ## Options

  This callback should support the following options:

    * `:stderr_to_stdout` - when `false`, does not redirect
      stderr to stdout

    * `:quiet` - when `true`, do not print the command output

    * `:env` - environment options to the executed command

    * `:cd` - the directory to run the command in

  All the built-in shells support these.
  """
  @callback cmd(command :: String.t(), options :: cmd_opts) :: integer
end
