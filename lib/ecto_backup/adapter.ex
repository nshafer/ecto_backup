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

  This should return `{:ok, backup_file}` on success, where `backup_file` is the path to the created
  backup file. On failure, it should return `{:error, %EctoBackup.Error{}}` with details about the failure.

  Effort should be made to not throw exceptions from this function; instead, return errors in the
  specified format.

  ## Parameters

    - `repo`        - The Ecto repository module to back up.
    - `repo_config` - A map of repository-specific options, merged from various configuration sources.
    - `file`        - The path to the backup file where the database dump should be stored.
    - `options`     - A map of additional options passed to the backup operation.
  """
  @callback backup(
              repo :: Ecto.Repo.t(),
              file :: String.t(),
              repo_config :: map(),
              options :: map()
            ) ::
              {:ok, String.t()} | {:error, %EctoBackup.Error{}}

  @doc """
  Restores a backup for the given repository from the specified file.

  ## Parameters

    - `repo`        - The Ecto repository module to restore.
    - `repo_config` - A map of repository-specific options, merged from various configuration sources.
    - `file`        - The path to the backup file from which the database dump should be restored.
    - `options`     - A map of additional options passed to the restore operation.
  """

  # @callback restore(
  #             repo :: Ecto.Repo.t(),
  #             file :: String.t(),
  #             repo_config :: map(),
  #             options :: map()
  #           ) ::
  #             :ok | {:error, term()}

  @spec backup(Ecto.Repo.t(), map(), String.t(), map()) ::
          {:ok, String.t()} | {:error, %EctoBackup.Error{}}
  def backup(repo, repo_config, file, options) do
    adapter_module(repo, repo_config).backup(repo, repo_config, file, options)
  end

  # def restore(repo, repo_config, file, options) do
  #   adapter_module(repo, repo_config).restore(repo, repo_config, file, options)
  # end

  defp adapter_module(_repo, %{adapter: adapter}) when is_atom(adapter) do
    adapter
  end

  defp adapter_module(repo, _repo_config) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> EctoBackup.Adapters.Postgres
      adapter -> raise_unsupported_ecto_adapter_error(repo, adapter)
    end
  end

  defp raise_unsupported_ecto_adapter_error(repo, adapter) do
    raise EctoBackup.Error,
      reason: :unsupported_ecto_adapter,
      repo: repo,
      message: "unsupported Ecto adapter #{inspect(adapter)} for repo #{inspect(repo)}"
  end
end
