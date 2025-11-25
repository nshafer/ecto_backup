defmodule EctoBackup.CLI.Shell.Quiet do
  # An EctoBackup CLI shell that suppresses all output.

  @moduledoc false

  @behaviour EctoBackup.CLI.Shell

  @doc """
  Prints nothing to the shell.
  """
  @impl true
  def info(_) do
    :ok
  end

  @doc """
  Prints the warning message using Mix.CLI.Shell.IO.warning/1.
  """
  @impl true
  defdelegate warning(message), to: EctoBackup.CLI.Shell.IO

  @doc """
  Prints the error message using Mix.CLI.Shell.IO.error/1.
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
end
