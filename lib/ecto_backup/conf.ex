defmodule EctoBackup.Conf do
  @moduledoc """
  Module for managing Ecto repository configurations for backups.

  This module provides functions to gather and merge repository configurations
  from various sources, including the repo's own configuration, application
  environment overrides, and runtime options.

  This is intended to be used by EctoBackup adapters.
  """

  @doc """
  Fetches the value for the given key from the provided options, repo_config, or :ecto_backup environment.

  Returns `{:ok, value}` if found, or `:error` if the key is not present in any of the sources.
  """
  @spec fetch(map, map, atom) :: {:ok, term} | :error
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
  @spec fetch!(map, map, atom) :: term
  def fetch!(repo_config, options, key) do
    case fetch(repo_config, options, key) do
      {:ok, value} -> value
      :error -> raise KeyError, "missing required configuration key #{inspect(key)}"
    end
  end

  @doc """
  Like `fetch/3`, but returns the provided default value if the key is not found.
  """
  @spec get(map, map, atom, term) :: term
  def get(repo_config, options, key, default) do
    case fetch(repo_config, options, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  # These are defined here, publicly, but undocumented so we can easily test them without patching/mocking.

  @doc false
  @spec get_repo_configs([atom | {atom, keyword}]) :: {:ok, [{atom, map}]} | {:error, term}
  def get_repo_configs([]) do
    with {:ok, repos} <- get_default_repos() do
      get_repo_configs(repos)
    end
  end

  def get_repo_configs(repo_specs) when is_list(repo_specs) do
    {:ok, Enum.map(repo_specs, &merge_repo_configs/1)}
  end

  defp merge_repo_configs(repo_spec) do
    {repo, override_config} =
      case repo_spec do
        {repo_module, config} when is_atom(repo_module) ->
          {repo_module, Map.new(config)}

        repo_module when is_atom(repo_module) ->
          {repo_module, %{}}

        other ->
          raise ArgumentError,
                "invalid repo specification, expected atom " <>
                  "or {atom, keyword}, got: #{inspect(other)}"
      end

    repo_config = repo_config(repo)
    app_repo_config = Application.get_env(:ecto_backup, repo, %{}) |> Map.new()

    merged_config =
      repo_config
      |> Map.merge(app_repo_config)
      |> Map.merge(override_config)

    {repo, merged_config}
  end

  defp repo_config(repo) do
    if Code.ensure_loaded?(repo) and function_exported?(repo, :__adapter__, 0) do
      case repo.config() do
        config when is_list(config) -> Map.new(config)
        _ -> raise "invalid repo config returned from #{inspect(repo)}.config/0"
      end
    else
      raise ArgumentError, "#{inspect(repo)} is not a valid Ecto.Repo module"
    end
  end

  @doc false
  @spec get_default_repos() :: {:ok, [atom]} | {:error, term}
  def get_default_repos() do
    # Check for an explicit config for `:ecto_repos` in `:ecto_backup` app env
    case Application.fetch_env(:ecto_backup, :ecto_repos) do
      {:ok, repos} when is_list(repos) ->
        {:ok, repos}

      :error ->
        # If Mix is available, then try to get the repos from the current project, which is what Ecto
        # requires for use of its tasks: https://hexdocs.pm/ecto/Ecto.html#module-mix-tasks-and-generators
        if Code.ensure_loaded?(Mix.Project) do
          apps =
            if apps_paths = Mix.Project.apps_paths() do
              Enum.filter(Mix.Project.deps_apps(), &is_map_key(apps_paths, &1))
            else
              [Mix.Project.config()[:app]]
            end

          repos =
            apps
            |> Enum.flat_map(fn app ->
              Application.load(app)
              Application.get_env(app, :ecto_repos, [])
            end)
            |> Enum.uniq()

          case repos do
            [] -> {:error, :no_default_repos}
            repos -> {:ok, repos}
          end
        else
          # If Mix is not available, we cannot determine the default repos
          {:error, :no_default_repos}
        end
    end
  end

  @doc false
  def get_backup_file(repo_config, options) do
    case fetch(repo_config, options, :backup_file) do
      {:ok, file} when is_binary(file) -> {:ok, file}
      {:ok, other} -> {:error, ":backup_file must be a string, got: #{inspect(other)}"}
      :error -> default_backup_file(repo_config, options)
    end
  end

  defp default_backup_file(repo_config, options) do
    with {:ok, backup_dir} <- fetch(repo_config, options, :backup_dir) do
      timestamp = DateTime.to_iso8601(DateTime.utc_now())
      backup_name = repo_config[:database] || "ecto"
      {:ok, Path.join(backup_dir, "#{backup_name}_backup_#{timestamp}.db")}
    else
      :error -> {:error, "no backup_file or backup_dir specified in options or configuration"}
    end
  end
end
