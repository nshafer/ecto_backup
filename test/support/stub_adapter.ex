defmodule EctoBackup.StubAdapter do
  alias EctoBackup.Error

  @behaviour EctoBackup.Adapter

  @data "stub backup data\n"

  @impl true
  def backup(repo, _repo_config, "invalid_backup_file.db", _options) do
    {:error,
     Error.exception(
       reason: :invalid_backup_file,
       message: "Invalid backup file",
       repo: repo
     )}
  end

  def backup(_repo, _repo_config, backup_file, _options) do
    with :ok <- File.write(backup_file, @data) do
      {:ok, backup_file}
    end
  end

  @impl true
  def restore(_repo, _repo_config, restore_file, _options) do
    with {:ok, content} <- File.read(restore_file) do
      if content == @data do
        :ok
      else
        {:error, :invalid_backup_data}
      end
    end
  end

  def create_backup_dir!() do
    Temp.track!()
    Temp.mkdir!(prefix: "ecto_backup_stub_")
  end
end
