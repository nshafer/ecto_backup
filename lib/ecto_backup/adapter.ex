defmodule EctoBackup.Adapter do
  @moduledoc """
  Behaviour module defining the interface for database backup adapters.

  Also includes some helper functions for Adapters to use.
  """

  @doc """
  Performs a backup of the given repository to the specified file.

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
              {:ok, String.t()} | {:error, term()}

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
      other -> raise "Unsupported adapter #{inspect(other)} for repo #{inspect(repo)}"
    end
  end
end
