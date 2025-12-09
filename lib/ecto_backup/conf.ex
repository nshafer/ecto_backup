defmodule EctoBackup.Conf do
  @moduledoc """
  Helper functions for fetching configuration values merged from options, repo config, and
  application environment.

  This is intended to be used by EctoBackup adapters.
  """
  @type repo_spec :: atom | {atom, keyword}
  @type repo_config :: map()
  @type options :: map()

  @doc """
  Fetches the value for the given key from the provided options, repo_config, or :ecto_backup environment.

  Returns `{:ok, value}` if found, or `:error` if the key is not present in any of the sources.
  """
  @spec fetch(repo_config(), options(), atom()) :: {:ok, term()} | :error
  def fetch(repo_config, options, key) do
    with(
      :error <- Map.fetch(options, key),
      :error <- Map.fetch(repo_config, key),
      :error <- Application.fetch_env(:ecto_backup, key)
    ) do
      :error
    end
  end

  @doc """
  Like `fetch/3`, but raises `KeyError` if the key is not found.
  """
  @spec fetch!(repo_config(), options(), atom()) :: term()
  def fetch!(repo_config, options, key) do
    case fetch(repo_config, options, key) do
      {:ok, value} ->
        value

      :error ->
        raise KeyError,
          key: key,
          term: [
            options: options,
            repo_config: repo_config,
            app_env: Application.get_all_env(:ecto_backup)
          ]
    end
  end

  @doc """
  Like `fetch/3`, but returns the provided default value if the key is not found.
  """
  @spec get(repo_config(), options(), atom(), term()) :: term()
  def get(repo_config, options, key, default) do
    case fetch(repo_config, options, key) do
      {:ok, value} -> value
      :error -> default
    end
  end
end
