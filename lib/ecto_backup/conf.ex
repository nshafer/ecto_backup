defmodule EctoBackup.Conf do
  @moduledoc """
  Module for managing Ecto repository configurations for backups.

  This module provides functions to gather and merge repository configurations
  from various sources, including the repo's own configuration, application
  environment overrides, and runtime options.

  This is intended to be used by EctoBackup adapters.
  """
  alias EctoBackup.ConfError

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

  # These are defined here, publicly, but undocumented so we can easily test them without
  # patching/mocking.

  @doc false
  # Retrieves the repository configurations for the given list of repository specifications. If
  # the list is empty, retrieves the default repositories from application configuration. Merges
  # configurations from the repo, application env, and overrides.
  @spec get_repo_configs([repo_spec()]) ::
          {:ok, [{Ecto.Repo.t(), repo_config()}]} | {:error, Exception.t()}
  def get_repo_configs([]) do
    with {:ok, repos} <- get_default_repos() do
      get_repo_configs(repos)
    end
  end

  def get_repo_configs(repo_specs) when is_list(repo_specs) do
    {:ok, Enum.map(repo_specs, &merge_repo_configs!/1)}
  rescue
    e in ConfError ->
      {:error, e}
  end

  defp merge_repo_configs!(repo_spec) do
    {repo, override_config} =
      case repo_spec do
        {repo_module, config} when is_atom(repo_module) -> {repo_module, Map.new(config)}
        repo_module when is_atom(repo_module) -> {repo_module, %{}}
        other -> raise ConfError, reason: :invalid_repo_spec, value: other
      end

    repo_config = get_repo_config!(repo)
    app_repo_config = Application.get_env(:ecto_backup, repo, %{}) |> Map.new()

    merged_config =
      repo_config
      |> Map.merge(app_repo_config)
      |> Map.merge(override_config)

    {repo, merged_config}
  end

  defp get_repo_config!(repo) do
    if Code.ensure_loaded?(repo) and function_exported?(repo, :__adapter__, 0) do
      case repo.config() do
        config when is_list(config) -> Map.new(config)
        config -> raise ConfError, reason: :invalid_repo_config, repo: repo, value: config
      end
    else
      raise ConfError, reason: :invalid_repo, repo: repo
    end
  end

  @doc false
  # Retrieves the default repositories from application configuration. First checks
  # for an explicit `:ecto_repos` config in the `:ecto_backup` app env, then
  # falls back to checking the current Mix project if available.
  @spec get_default_repos() :: {:ok, [Ecto.Repo.t()]} | {:error, Exception.t()}
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
            [] -> {:error, ConfError.exception(reason: :no_default_repos_in_mix)}
            repos -> {:ok, repos}
          end
        else
          {:error, ConfError.exception(reason: :no_default_repos)}
        end
    end
  end

  @doc false
  # Return a list of backup file paths for the given list of repo configurations and options. If
  # any repo configuration does not have a valid backup file path, raises an error.
  @spec get_backup_files([{Ecto.Repo.t(), repo_config()}], options()) ::
          {:ok, [String.t()]} | {:error, Exception.t()}
  def get_backup_files(repo_configs, options) do
    backup_files =
      for {repo, repo_config} <- repo_configs do
        get_backup_file!(repo, repo_config, options)
      end

    {:ok, backup_files}
  rescue
    e in [ConfError] ->
      {:error, e}
  end

  @doc false
  # Return the backup file path for the given repo configuration and options. If not
  # explicitly specified, constructs a default backup file path using the backup_dir
  # and a timestamped filename.
  @spec get_backup_file!(Ecto.Repo.t(), repo_config(), options()) ::
          {:ok, String.t()} | {:error, String.t()}
  def get_backup_file!(repo, repo_config, options) do
    case fetch(repo_config, options, :backup_file) do
      {:ok, file} when is_binary(file) ->
        file

      {:ok, fun} when is_function(fun, 2) ->
        fun.(repo, repo_config)

      {:ok, {m, f, a}} when is_atom(m) and is_atom(f) and is_list(a) ->
        apply(m, f, [repo, repo_config] ++ a)

      {:ok, other} ->
        raise ConfError, reason: :invalid_backup_file, repo: repo, value: other

      :error ->
        default_backup_file!(repo, repo_config, options)
    end
  end

  defp default_backup_file!(repo, repo_config, options) do
    case fetch(repo_config, options, :backup_dir) do
      {:ok, backup_dir} when is_binary(backup_dir) ->
        timestamp = DateTime.to_iso8601(DateTime.utc_now())
        backup_name = repo_to_filename(repo)
        Path.join(backup_dir, "#{backup_name}_backup_#{timestamp}.db")

      {:ok, invalid} ->
        raise ConfError, reason: :invalid_backup_dir, repo: repo, value: invalid

      :error ->
        raise ConfError, reason: :no_backup_dir_set, repo: repo
    end
  end

  def repo_to_filename(repo) do
    repo
    |> Module.split()
    |> Enum.map(&Macro.underscore/1)
    |> Enum.join("_")
  end
end
