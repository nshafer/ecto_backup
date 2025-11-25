defmodule EctoBackup.CLI.Shell.Process do
  # An EctoBackup CLI shell that sends output to another process. This is mainly for use in tests.

  @moduledoc false

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

  @impl true
  def info(message) do
    send(self(), {:ecto_backup_shell, :info, format(message)})
    :ok
  end

  @impl true
  def warning(message) do
    send(self(), {:ecto_backup_shell, :warning, format(message)})
    :ok
  end

  @impl true
  def error(message) do
    send(self(), {:ecto_backup_shell, :error, format(message)})
    :ok
  end

  @impl true
  def status(nil) do
    :ok
  end

  def status(message) do
    send(self(), {:ecto_backup_shell, :status, format(message)})
    :ok
  end

  defp format(message) do
    message |> IO.ANSI.format(false) |> IO.iodata_to_binary()
  end
end
