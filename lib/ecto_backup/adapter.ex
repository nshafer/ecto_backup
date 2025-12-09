defmodule EctoBackup.Adapter do
  @moduledoc """
  Behaviour module defining the interface for database backup adapters.

  Also includes some helper functions for Adapters to use.

  ## Telemetry Events

  During backup and restore operations, the following telemetry events can optionally emitted by
  the adapter during backup. The core backup facilities will listen for these events and provide
  additional functionality, such as progress bars and log lines during the process.

  ### Message

  Event name: `[:ecto_backup, :backup, :repo, :message]`

  Emitted to log a message during the backup or restore process. The metadata must include:

    - `:repo`        - The Ecto repository module being backed up or restored.
    - `:level`       - The log level, one of `:info`, `:warning`, or `:error`.
    - `:message`     - The log message string.

  ### Progress

  Event name: `[:ecto_backup, :backup, :repo, :progress]`

  Emitted to indicate progress during the backup or restore process. The measurements must
  include:

    - `:completed`  - The number of units completed (e.g., bytes, tables, etc.).
    - `:total`      - The total number of units to complete.

  The metadata must include:

    - `:repo`       - The Ecto repository module being backed up or restored.
    - `:subject`    - (optional) A string indicating the subject of the progress (e.g., table
      name) or `nil` for a default subject.
    - `:label`      - (optional) A label for the measurement, e.g., `"MiB"`, `GB`, etc.

  """

  @doc """
  Performs a backup of the given repository to the specified file.

  This should return `{:ok, backup_file}` on success, where `backup_file` is the path to the
  created backup file. On failure, it should return `{:error, %EctoBackup.Error{}}` with details
  about the failure.

  Effort should be made to not throw exceptions from this function; instead, return errors in the
  specified format.

  ## Parameters

    * `repo`         - The Ecto repository module to back up.

    * `repo_config`  - A map of repository-specific options, merged from various configuration
      sources.

    * `backup_file`  - The path to the backup file where the database dump should be stored.

    * `options`      - A map of additional options passed to the backup operation.
  """
  @callback backup(
              repo :: Ecto.Repo.t(),
              repo_config :: map(),
              backup_file :: String.t(),
              options :: map()
            ) ::
              {:ok, String.t()} | {:error, %EctoBackup.Error{}}

  @doc """
  Restores a backup for the given repository from the specified file.

  ## Parameters

    * `repo`         - The Ecto repository module to restore.

    * `repo_config`  - A map of repository-specific options, merged from various configuration
      sources.

    * `restore_file` - The path to the backup file from which the database dump should be
      restored.

    * `options`      - A map of additional options passed to the restore operation.
  """

  @callback restore(
              repo :: Ecto.Repo.t(),
              repo_config :: map(),
              restore_file :: String.t(),
              options :: map()
            ) ::
              :ok | {:error, term()}

  @spec backup(Ecto.Repo.t(), map(), String.t(), map()) ::
          {:ok, String.t()} | {:error, %EctoBackup.Error{}}
  def backup(repo, repo_config, backup_file, options) do
    case adapter_module(repo, repo_config) do
      {:ok, adapter} -> adapter.backup(repo, repo_config, backup_file, options)
      {:error, error} -> {:error, error}
    end
  end

  def restore(repo, repo_config, restore_file, options) do
    case adapter_module(repo, repo_config) do
      {:ok, adapter} -> adapter.restore(repo, repo_config, restore_file, options)
      {:error, error} -> {:error, error}
    end
  end

  defp adapter_module(_repo, %{adapter: adapter}) when is_atom(adapter) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :backup, 4) and
         function_exported?(adapter, :restore, 4) do
      {:ok, adapter}
    else
      {:error,
       EctoBackup.Error.exception(
         reason: :invalid_adapter,
         message: "invalid adapter module #{inspect(adapter)}"
       )}
    end
  end

  defp adapter_module(repo, _repo_config) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        {:ok, EctoBackup.Adapters.Postgres}

      adapter ->
        {:error,
         EctoBackup.Error.exception(
           reason: :unsupported_ecto_adapter,
           repo: repo,
           message: "unsupported Ecto adapter #{inspect(adapter)} for repo #{inspect(repo)}"
         )}
    end
  end
end
