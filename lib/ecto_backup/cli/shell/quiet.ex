defmodule EctoBackup.CLI.Shell.Quiet do
  @moduledoc """
  An EctoBackup CLI shell that suppresses all normal output.
  """

  @behaviour EctoBackup.CLI.Shell

  @doc """
  Prints nothing to the shell.
  """
  @impl true
  def info(_) do
    :ok
  end

  @doc """
  Prints the warning message using `EctoBackup.CLI.Shell.IO.warning/1`.
  """
  @impl true
  defdelegate warning(message), to: EctoBackup.CLI.Shell.IO

  @doc """
  Prints the error message using `EctoBackup.CLI.Shell.IO.error/1`.
  """
  @impl true
  defdelegate error(message), to: EctoBackup.CLI.Shell.IO

  @doc """
  Prints nothing to the shell.
  """
  @impl true
  def status(_) do
    :ok
  end

  @doc """
  Prompts the user for input using `EctoBackup.CLI.Shell.IO.prompt/1`.
  """
  @impl true
  defdelegate prompt(message), to: EctoBackup.CLI.Shell.IO

  @doc """
  Executes the given command quietly without outputting anything.
  """
  @impl true
  def cmd(command, opts \\ []) do
    EctoBackup.CLI.cmd(command, opts)
  end
end
