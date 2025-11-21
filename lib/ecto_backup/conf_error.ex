defmodule EctoBackup.ConfError do
  @moduledoc """
  Exception module for EctoBackup configuration errors.
  """
  defexception [:reason, :repo, :value, :message]

  def message(%{message: message}) when is_binary(message), do: message

  def message(%{reason: :no_default_repos_in_mix}) do
    """
    no default repositories found, please configure :ecto_repos in your application configuration
    or in the :ecto_backup application configuration. Examples:

        config :my_app, ecto_repos: [MyApp.Repo]
        config :ecto_backup, ecto_repos: [MyApp.Repo]
    """
  end

  def message(%{reason: :no_default_repos}) do
    """
    no default repositories found, please configure :ecto_repos in the :ecto_backup application
    configuration. This is required when Mix is not available. Example:

        config :ecto_backup, ecto_repos: [MyApp.Repo]
    """
  end

  def message(%{reason: :invalid_repo_spec, value: repo_spec}) do
    "invalid repo specification, expected atom or {atom, keyword}, got: #{inspect(repo_spec)}"
  end

  def message(%{reason: :invalid_repo_config, repo: repo, value: config}) do
    "invalid repo config returned from #{inspect(repo)}.config/0, got: #{inspect(config)}"
  end

  def message(%{reason: :invalid_repo, repo: repo}) do
    "#{inspect(repo)} is not a valid Ecto.Repo module"
  end

  def message(%{reason: :invalid_backup_file, value: invalid}) do
    "invalid backup file path, expected a string, got #{inspect(invalid)}"
  end

  def message(%{reason: :invalid_backup_dir, value: invalid}) do
    "invalid backup directory path, expected a string, got #{inspect(invalid)}"
  end

  def message(%{reason: :no_backup_dir_set}) do
    """
    no backup directory is set, so a backup file cannot be generated, please set the :backup_dir
    option or specify a :backup_file in the repo configuration. Example:

        config :ecto_backup, backup_dir: "/path/to/backup/dir"
    """
  end
end
