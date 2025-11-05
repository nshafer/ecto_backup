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

  @doc """
  Invokes the appropriate callback function for the given event type if an update callback is
  specified in the options.

  ## Parameters

    - `type`    - The type of event (:started, :message, :progress, :completed).
    - `options` - A map of options that may include a `:callback` key.
    - `repo`    - The Ecto repository module associated with the event.
    - `data`    - A map containing event-specific data.

  ## Required keys in `data` based on `type`

    - `:started` - `:repo_config`.
    - `:message` - `:level`, `:message`.
    - `:progress` - `:percent`.
    -  `:completed` - `:result`.

    Adapters may pass additional keys in the `data` map as needed, but should document them
    clearly.

    See `EctoBackup.backup/1` for details on the `update` parameter.

  """
  def call_update(:started, %{update: callback}, repo, %{repo_config: repo_config})
      when is_function(callback, 3) and is_atom(repo) and is_map(repo_config) do
    callback.(:started, repo, %{repo_config: repo_config})
  end

  def call_update(:started, %{update: {m, f, a}}, repo, %{repo_config: repo_config})
      when is_atom(m) and is_atom(f) and is_list(a) and is_atom(repo) and is_map(repo_config) do
    apply(m, f, [:started, repo, %{repo_config: repo_config} | a])
  end

  def call_update(:message, %{update: callback}, repo, %{level: level, message: message})
      when is_function(callback, 3) and is_atom(repo) and is_atom(level) and is_binary(message) do
    callback.(:message, repo, %{level: level, message: message})
  end

  def call_update(:message, %{update: {m, f, a}}, repo, %{level: level, message: message})
      when is_atom(m) and is_atom(f) and is_list(a) and is_atom(repo) and is_atom(level) and
             is_binary(message) do
    apply(m, f, [:message, repo, %{level: level, message: message} | a])
  end

  def call_update(:progress, %{update: callback}, repo, %{percent: percent})
      when is_function(callback, 3) and is_atom(repo) and is_float(percent) do
    callback.(:progress, repo, %{percent: percent})
  end

  def call_update(:progress, %{update: {m, f, a}}, repo, %{percent: percent})
      when is_atom(m) and is_atom(f) and is_list(a) and is_atom(repo) and is_float(percent) do
    apply(m, f, [:progress, repo, %{percent: percent} | a])
  end

  def call_update(:completed, %{update: callback}, repo, %{result: result})
      when is_function(callback, 3) and is_atom(repo) and is_tuple(result) do
    callback.(:completed, repo, %{result: result})
  end

  def call_update(:completed, %{update: {m, f, a}}, repo, %{result: result})
      when is_atom(m) and is_atom(f) and is_list(a) and is_atom(repo) and is_tuple(result) do
    apply(m, f, [:completed, repo, %{result: result} | a])
  end

  def call_update(_type, _options, _repo, _data), do: :ok
end
