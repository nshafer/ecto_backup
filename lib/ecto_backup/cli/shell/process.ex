defmodule EctoBackup.CLI.Shell.Process do
  @moduledoc """
  An EctoBackup CLI shell that sends output to another process.

  This is mainly for use in tests.

  Any ANSI codes in the messages are stripped before sending.
  """

  @behaviour EctoBackup.CLI.Shell

  @doc """
  Flushes all `:ecto_backup_shell` and `:ecto_backup_shell_input` messages from the current
  process.

  If a callback is given, it is invoked for each received message.

  ## Examples

      flush(&IO.inspect/1)

  """
  def flush(callback \\ fn x -> x end) do
    receive do
      {:ecto_backup_shell, _, _} = message ->
        callback.(message)
        flush(callback)
    after
      0 -> :done
    end
  end

  @doc """
  Sends a message to the current process indicating an informational message.

  Format is `{:ecto_backup_shell, :info, message}`.
  """
  @impl true
  def info(message) do
    send(self(), {:ecto_backup_shell, :info, format(message)})
    :ok
  end

  @doc """
  Sends a message to the current process indicating a warning message.

  Format is `{:ecto_backup_shell, :warning, message}`.
  """
  @impl true
  def warning(message) do
    send(self(), {:ecto_backup_shell, :warning, format(message)})
    :ok
  end

  @doc """
  Sends a message to the current process indicating an error message.

  Format is `{:ecto_backup_shell, :error, message}`.
  """
  @impl true
  def error(message) do
    send(self(), {:ecto_backup_shell, :error, format(message)})
    :ok
  end

  @doc """
  Sends a message to the current process indicating a status message.

  Does not send anything if the message is `nil`, which indicates a desire to clear the status.

  Format is `{:ecto_backup_shell, :status, message}`.
  """
  @impl true
  def status(nil) do
    :ok
  end

  def status(message) do
    send(self(), {:ecto_backup_shell, :status, format(message)})
    :ok
  end

  @doc """
  Sends the given prompt message to the current process and checks for a message response.

  Format is `{:ecto_backup_shell, :prompt, message}`.

  Expects a response in the form `{:ecto_backup_shell_input, :prompt, input}`.

  Example:

      send(self(), {:ecto_backup_shell_input, :prompt, "Thom"})
      EctoBackup.CLI.shell().prompt("Enter name:")

  """
  @impl true
  def prompt(message) do
    send(self(), {:ecto_backup_shell, :prompt, format(message)})

    receive do
      {:ecto_backup_shell_input, :prompt, input} -> input
    after
      0 -> raise "No input received for prompt"
    end
  end

  @doc """
  Executes the given command and forwards its messages to the current process.

  Format is
  """
  @impl true
  def cmd(command, opts \\ []) do
    on_output = fn data ->
      send(self(), {:ecto_backup_shell, :cmd, data})
    end

    EctoBackup.CLI.cmd(command, Keyword.put(opts, :on_output, on_output))
  end

  defp format(message) do
    message |> IO.ANSI.format(false) |> IO.iodata_to_binary()
  end
end
