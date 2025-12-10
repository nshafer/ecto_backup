defmodule EctoBackup.StubAdapter do
  alias EctoBackup.Error

  @behaviour EctoBackup.Adapter

  @data "stub backup data\n"

  @impl true
  def backup(repo, _repo_config, "invalid_backup_file.db", _options) do
    emit_message_event(:backup, :error, repo, "Invalid backup file")

    {:error,
     Error.exception(
       reason: :invalid_backup_file,
       message: "Invalid backup file",
       repo: repo
     )}
  end

  def backup(repo, _repo_config, backup_file, _options) do
    emit_message_event(:backup, :info, repo, "dumping stub data")
    emit_progress_event(:backup, repo, 0, 1, "stub backup progress")

    with :ok <- File.write(backup_file, @data) do
      emit_message_event(:backup, :info, repo, "stub data written to #{backup_file}")
      emit_progress_event(:backup, repo, 1, 1, "stub backup progress")

      {:ok, backup_file}
    end
  end

  @impl true
  def restore(repo, _repo_config, "invalid_restore_file.db", _options) do
    emit_message_event(:restore, :error, repo, "Invalid restore file")

    {:error,
     Error.exception(
       reason: :invalid_restore_file,
       message: "Invalid restore file",
       repo: repo
     )}
  end

  def restore(repo, _repo_config, restore_file, _options) do
    emit_message_event(:restore, :info, repo, "restoring stub data")
    emit_progress_event(:restore, repo, 0, 1, "stub restore progress")

    with {:ok, content} <- File.read(restore_file) do
      emit_progress_event(:restore, repo, 1, 1, "stub restore progress")

      if content == @data do
        emit_message_event(:restore, :info, repo, "stub data restored successfully")
        :ok
      else
        emit_message_event(:restore, :error, repo, "invalid backup data")

        {:error,
         Error.exception(
           reason: :invalid_backup_data,
           message: "invalid backup data",
           repo: repo
         )}
      end
    end
  end

  def create_backup_dir!() do
    Temp.track!()
    Temp.mkdir!(prefix: "ecto_backup_stub_")
  end

  defp emit_progress_event(op, repo, completed, total, subject) do
    measurements = %{
      completed: completed,
      total: total
    }

    metadata = %{
      repo: repo,
      subject: subject
    }

    :telemetry.execute([:ecto_backup, op, :repo, :progress], measurements, metadata)
  end

  defp emit_message_event(op, level, repo, message) do
    metadata = %{
      repo: repo,
      level: level,
      message: message
    }

    :telemetry.execute([:ecto_backup, op, :repo, :message], %{}, metadata)
  end
end
