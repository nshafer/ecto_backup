defmodule EctoBackup.Adapter do
  @moduledoc """
  Behaviour module defining the interface for database backup adapters.

  An adapter is responsible for performing the actual backup and restore operations for a specific
  database type. The minimum requirement is to implement the `backup/3` and `restore/3` functions.
  If possible, the adapter should avoid raising exceptions and instead return errors in the
  specified format. Also, adapters can emit telemetry events during the backup and restore process
  to provide progress updates and log messages, which is how the mix and release tasks provide
  feedback to the user.

  If backup or restore operations don't make sense for a particular database type, the adapter
  should return an appropriate error from the `backup/3` or `restore/3` functions.

  ## Naming Convention

  First-party adapters are provided in the `EctoBackup.Adapters` namespace, and packaged either in
  the `ecto_backup` library itself or in official companion libraries (e.g. `ecto_backup_foodb`)
  if it requires dependencies that we don't want to include in the core library.

  Only adapters to which this project takes on the burden of maintenance and support will be
  included in official libraries. This does not necessarily mean that first-party adapters are
  superior to third-party adapters; each should be evaluated on its own merits.

  Third-party libraries should start with `ecto_backup` in their package names, and their modules
  should be provided in their own namespaces, not under the `EctoBackup` namespace. For example, a
  third-party adapter for a hypothetical "FooDB" database should be packaged in a library named
  `ecto_backup_foodb` and have a module named something like `EctoBackupFooDB`, which is the
  module that implements this behaviour.

  ## Telemetry Events

  During backup and restore operations, the following telemetry events can optionally emitted by
  the adapter during backup. The core backup facilities will listen for these events and provide
  additional functionality, such as progress bars and log lines during the process.

  ### Message

  Events:

    - `[:ecto_backup, :backup, :repo, :message]`
    - `[:ecto_backup, :restore, :repo, :message]`

  Emitted to log a message during the backup or restore process.

  The metadata must include:

    - `:repo`        - The Ecto repository module being backed up or restored.
    - `:level`       - The log level, one of `:info`, `:warning`, or `:error`.
    - `:message`     - The log message string.

  ### Progress

  Events:

    - `[:ecto_backup, :backup, :repo, :progress]`
    - `[:ecto_backup, :restore, :repo, :progress]`

  Emitted to indicate progress during the backup or restore process.

  The measurements must include:

    - `:completed`  - The number of units completed (e.g., bytes, tables, etc.).
    - `:total`      - The total number of units to complete.

  The metadata must include:

    - `:repo`       - The Ecto repository module being backed up or restored.

  The metadata may optionally include:

    - `:subject`    - A string indicating the subject of the progress (e.g., table name) or `nil`
      for a default subject.
    - `:label`      - A label for the measurement, e.g., `"MiB"`, `GB`, etc.

  """

  @doc """
  Performs a backup of the given repository to the `:backup_file` specified in the `repo_config`.

  This should return `{:ok, backup_file}` on success, where `backup_file` is the path to the
  created backup file. On failure, it should return `{:error, %EctoBackup.Error{}}` with details
  about the failure.

  Effort should be made to not throw exceptions from this function; instead, return errors in the
  specified format.

  ## Parameters

    - `repo`         - The Ecto repository module to back up.
    - `repo_config`  - A map of repository-specific options, merged from various configuration
      sources.
    - `options`      - A map of additional options passed to the backup operation.
  """
  @callback backup(
              repo :: Ecto.Repo.t(),
              repo_config :: map(),
              options :: map()
            ) ::
              {:ok, String.t()} | {:error, %EctoBackup.Error{}}

  @doc """
  Restores a backup for the given repository from the specified `:restore_file` in the
  `repo_config`.

  This should return `{:ok, restore_file}` on success, where `restore_file` is the path to the
  used restore file. On failure, it should return `{:error, %EctoBackup.Error{}}` with details
  about the failure.

  Effort should be made to not throw exceptions from this function; instead, return errors in the
  specified format.

  ## Parameters

    - `repo`         - The Ecto repository module to restore.
    - `repo_config`  - A map of repository-specific options, merged from various configuration
      sources.
    - `options`      - A map of additional options passed to the restore operation.
  """

  @callback restore(
              repo :: Ecto.Repo.t(),
              repo_config :: map(),
              options :: map()
            ) ::
              {:ok, String.t()} | {:error, %EctoBackup.Error{}}

  @spec backup(Ecto.Repo.t(), map(), map()) :: {:ok, String.t()} | {:error, %EctoBackup.Error{}}
  def backup(repo, repo_config, options) do
    case adapter_module(repo, repo_config) do
      {:ok, adapter} -> adapter.backup(repo, repo_config, options)
      {:error, error} -> {:error, error}
    end
  end

  @spec restore(Ecto.Repo.t(), map(), map()) :: {:ok, String.t()} | {:error, %EctoBackup.Error{}}
  def restore(repo, repo_config, options) do
    case adapter_module(repo, repo_config) do
      {:ok, adapter} -> adapter.restore(repo, repo_config, options)
      {:error, error} -> {:error, error}
    end
  end

  defp adapter_module(_repo, %{adapter: adapter}) when is_atom(adapter) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :backup, 3) and
         function_exported?(adapter, :restore, 3) do
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
