defmodule EctoBackup.Util do
  @moduledoc """
  Miscellaneous utility functions for EctoBackup.
  """

  alias EctoBackup.Conf
  alias EctoBackup.ConfError
  alias EctoBackup.Error

  @type cmd_opts :: [
          {:cd, Path.t()}
          | {:on_output, (binary() -> term())}
          | {:into, Collectable.t() | nil}
          | {:lines, pos_integer()}
          | {:stderr_to_stdout, boolean()}
          | {:use_stdio, boolean()}
          | {:env, [{binary(), binary() | nil}]}
          | {:quiet, boolean()}
          | {atom(), term()}
        ]

  defmodule CMD do
    @moduledoc false
    defstruct [:callback, :into]
  end

  @doc """
  Executes the given `command`.

  `command` is either a string, to be executed as a `System.shell/2` command, or a `{executable,
  args}` to be executed via `System.cmd/3`.

  ## Options

    * `:on_output` - a callback function that receives each chunk of output as it is produced. By
    default output is streamed without any packet lengths via `Port`, so the callback may receive
    several lines and/or partial lines. If you want line-by-line output, use the `:lines` option.
    This may be a tuple `{acc, fun}` where `fun` is called with the accumulator and each chunk of
    output as its two arguments, and must return the updated accumulator.

    * `:into` - an IO device or collectable to send output to, defaults to `""`. If `:on_output`
      is also provided, the callback is invoked before sending output to `:into`. If `:on_output`
      is set then this may be set to `nil` to avoid collecting output.

    * `:lines` - read output line-by-line, expects an integer number of lines to buffer internally
      (1024 is a reasonable default)

    * `:cd` - the directory to run the command in

    * `:stderr_to_stdout` - redirects stderr to stdout, defaults to `true`, unless `:use_stdio` is
      set to `false`

    * `:use_stdio` - controls whether the command should use `stdin` / `stdout` / `stderr`,
      defaults to `true`

    * `:env` - a list of environment variables, defaults to `[]`

    * `:quiet` - overrides the `on_output` callback to do nothing

  """
  @spec cmd(String.t() | {String.t(), [String.t()]}, cmd_opts) ::
          exit_status :: non_neg_integer
  def cmd(command, options \\ []) do
    callback =
      if options[:quiet] do
        fn x -> x end
      else
        options[:on_output]
      end

    use_stdio = Keyword.get(options, :use_stdio, true)
    into = Keyword.get(options, :into, "")

    options =
      options
      |> Keyword.take([:cd, :stderr_to_stdout, :env, :use_stdio, :lines])
      |> Keyword.put(:into, %CMD{callback: callback, into: into})
      |> Keyword.put_new(:stderr_to_stdout, use_stdio)

    case command do
      {command, args} -> System.cmd(command, args, options)
      command when is_binary(command) -> System.shell(command, options)
    end
  end

  defimpl Collectable, for: CMD do
    def into(%CMD{callback: nil, into: nil}) do
      raise ArgumentError, "must set `:callback` and/or `:into`"
    end

    def into(%CMD{callback: nil, into: into}) do
      Collectable.into(into)
    end

    def into(%CMD{callback: {acc, fun}, into: nil}) when is_function(fun) do
      fun = fn
        acc, {:cont, data} -> fun.(acc, data)
        _, _ -> nil
      end

      {acc, fun}
    end

    def into(%CMD{callback: fun, into: nil}) do
      fun = fn
        _, {:cont, data} -> fun.(data)
        _, _ -> nil
      end

      {nil, fun}
    end

    def into(%CMD{callback: {cb_acc, cb_fun}, into: into}) when is_function(cb_fun) do
      {into_acc, into_fun} = Collectable.into(into)

      fun = fn
        {cb_acc, into_acc}, {:cont, data} ->
          {cb_fun.(cb_acc, data), into_fun.(into_acc, {:cont, data})}

        {_, into_acc}, :done ->
          into_fun.(into_acc, :done)

        {_, into_acc}, :halt ->
          into_fun.(into_acc, :halt)
      end

      {{cb_acc, into_acc}, fun}
    end

    def into(%CMD{callback: cb_fun, into: into}) when is_function(cb_fun) do
      {into_acc, into_fun} = Collectable.into(into)

      fun = fn
        into_acc, {:cont, data} ->
          cb_fun.(data)
          into_fun.(into_acc, {:cont, data})

        into_acc, command ->
          into_fun.(into_acc, command)
      end

      {into_acc, fun}
    end
  end

  @doc """
  Returns the current local timestamp formatted as "HH:MM:SS.mmm".
  """
  @spec timestamp() :: String.t()
  def timestamp() do
    st = :erlang.system_time(:millisecond)
    {{_, _, _}, {h, m, s}} = :calendar.system_time_to_local_time(st, :millisecond)
    "#{pad_i(h, 2)}:#{pad_i(m, 2)}:#{pad_i(s, 2)}.#{rem(st, 1000) |> pad_i(3)}"
  end

  defp pad_i(int, width) do
    int
    |> Integer.to_string()
    |> String.pad_leading(width, "0")
  end

  @doc """
  Returns a human-readable duration string given a duration and time_unit.
  """
  @spec duration(integer(), :native | :millisecond | :microsecond | :nanosecond) :: String.t()
  def duration(duration, time_unit \\ :native) do
    duration = System.convert_time_unit(duration, time_unit, :millisecond)

    cond do
      duration >= 60 * 60 * 1000 ->
        hours = div(duration, 60 * 60 * 1000)
        duration = rem(duration, 60 * 60 * 1000)
        minutes = div(duration, 60 * 1000)
        duration = rem(duration, 60 * 1000)
        seconds = Float.round(duration / 1000, 2)
        "#{hours}h #{minutes}m #{seconds}s"

      duration >= 60 * 1000 ->
        minutes = div(duration, 60 * 1000)
        duration = rem(duration, 60 * 1000)
        seconds = Float.round(duration / 1000, 2)
        "#{minutes}m #{seconds}s"

      duration >= 1000 ->
        seconds = Float.round(duration / 1000, 2)
        "#{seconds}s"

      true ->
        "#{duration}ms"
    end
  end

  @doc """
  Retrieves the repository specifications from the provided options or application environment.
  Returns a list of repo specifications or an error if the configuration is invalid.
  """
  def get_repo_specs(%{repos: repo_specs}) when is_list(repo_specs) do
    {:ok, repo_specs}
  end

  def get_repo_specs(%{repos: repo_specs}) do
    {:error, ConfError.exception(reason: :invalid_repo_list, value: repo_specs)}
  end

  def get_repo_specs(_options) do
    case Application.fetch_env(:ecto_backup, :repos) do
      {:ok, []} -> {:error, ConfError.exception(reason: :no_repos_to_backup)}
      {:ok, repos} when is_list(repos) -> {:ok, repos}
      {:ok, invalid} -> {:error, ConfError.exception(reason: :invalid_repo_list, value: invalid)}
      :error -> {:error, ConfError.exception(reason: :no_default_repos)}
    end
  end

  @doc """
  Retrieves a single repository specification from the provided options or application
  environment. Returns the repo specification or an error if the configuration is invalid.
  """
  def get_repo_spec(%{repo: repo_spec}) do
    {:ok, repo_spec}
  end

  def get_repo_spec(_options) do
    case Application.fetch_env(:ecto_backup, :repos) do
      {:ok, [repo_spec]} -> {:ok, repo_spec}
      {:ok, []} -> {:error, ConfError.exception(reason: :no_repos_to_restore)}
      {:ok, _multiple} -> {:error, ConfError.exception(reason: :multiple_repos_to_restore)}
      :error -> {:error, ConfError.exception(reason: :no_default_repos)}
    end
  end

  @doc """
  Retrieves the repository configurations for the given list of repository specifications. Merges
  configurations from the repo, application env, and overrides. Returns a list of tuples of
  `{repo_module, merged_config}` or an error if any configuration is invalid.
  """
  def get_repo_configs([]) do
    {:error, ConfError.exception(reason: :no_repos_to_backup, value: [])}
  end

  def get_repo_configs(repo_specs) when is_list(repo_specs) do
    {:ok, Enum.map(repo_specs, &merge_repo_configs!/1)}
  rescue
    e in ConfError ->
      {:error, e}
  end

  # Merges the configuration for a single repository specification from the repo, application env,
  # and overrides. Returns a tuple of `{repo_module, merged_config}` or raises `ConfError` if the
  # configuration is invalid.
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

  # Retrieves the base configuration for the given repository module by calling its `config/0`
  # function. Raises `ConfError` if the repo module is invalid or returns an invalid
  # configuration.
  defp get_repo_config!(repo) do
    if Code.ensure_loaded?(repo) and function_exported?(repo, :config, 0) do
      case repo.config() do
        config when is_list(config) -> Map.new(config)
        config -> raise ConfError, reason: :invalid_repo_config, repo: repo, value: config
      end
    else
      raise ConfError, reason: :invalid_repo, repo: repo
    end
  end

  @doc """
  Return a list of backup file paths for the given list of repo configurations and options. If
  any repo configuration does not have a valid backup file path, returns an error.
  """
  def get_backup_files(repo_configs, options) do
    backup_files =
      for {repo, repo_config} <- repo_configs do
        get_backup_file!(repo, repo_config, options)
      end

    {:ok, backup_files}
  rescue
    e in ConfError ->
      {:error, e}
  end

  # Return the backup file path for the given repo configuration and options. If not
  # explicitly specified, constructs a default backup file path using the backup_dir
  # and a timestamped filename.
  defp get_backup_file!(repo, repo_config, options) do
    case Conf.fetch(repo_config, options, :backup_file) do
      {:ok, file} when is_binary(file) ->
        file

      {:ok, fun} when is_function(fun, 2) ->
        backup_file = fun.(repo, repo_config)

        if is_binary(backup_file) do
          backup_file
        else
          raise ConfError, reason: :invalid_backup_file, repo: repo, value: backup_file
        end

      {:ok, {m, f, a}} when is_atom(m) and is_atom(f) and is_list(a) ->
        backup_file = apply(m, f, [repo, repo_config] ++ a)

        if is_binary(backup_file) do
          backup_file
        else
          raise ConfError, reason: :invalid_backup_file, repo: repo, value: backup_file
        end

      {:ok, other} ->
        raise ConfError, reason: :invalid_backup_file, repo: repo, value: other

      :error ->
        default_backup_file!(repo, repo_config, options)
    end
  end

  # Constructs a default backup file path using the backup_dir and a timestamped filename.
  defp default_backup_file!(repo, repo_config, options) do
    backup_dir = get_backup_dir!(repo, repo_config, options)
    Path.join(backup_dir, "#{repo_to_filename(repo)}_backup_#{filename_timestamp()}.db")
  end

  # Retrieves the backup directory from the repo configuration or options. Raises `ConfError` if
  # the backup directory is not set or invalid.
  defp get_backup_dir!(repo, repo_config, options) do
    case Conf.fetch(repo_config, options, :backup_dir) do
      {:ok, backup_dir} when is_binary(backup_dir) ->
        backup_dir

      {:ok, fun} when is_function(fun, 2) ->
        backup_dir = fun.(repo, repo_config)

        if is_binary(backup_dir) do
          backup_dir
        else
          raise ConfError, reason: :invalid_backup_dir, repo: repo, value: backup_dir
        end

      {:ok, {m, f, a}} when is_atom(m) and is_atom(f) and is_list(a) ->
        backup_dir = apply(m, f, [repo, repo_config] ++ a)

        if is_binary(backup_dir) do
          backup_dir
        else
          raise ConfError, reason: :invalid_backup_dir, repo: repo, value: backup_dir
        end

      {:ok, invalid} ->
        raise ConfError, reason: :invalid_backup_dir, repo: repo, value: invalid

      :error ->
        raise ConfError, reason: :no_backup_dir_set, repo: repo
    end
  end

  # Returns a timestamp string suitable for filenames.
  defp filename_timestamp() do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
    |> String.replace(":", "-")
  end

  # Converts a repository module to a filename-friendly format.
  defp repo_to_filename(repo) do
    repo
    |> Module.split()
    |> Enum.map(&Macro.underscore/1)
    |> Enum.join("_")
  end

  @doc """
  Ensures the restore file is valid and exists.
  """
  def ensure_restore_file(restore_file) when is_binary(restore_file) do
    if File.exists?(restore_file) and File.regular?(restore_file) do
      {:ok, restore_file}
    else
      {:error,
       Error.exception(
         reason: :invalid_restore_file,
         message: "Restore file is invalid or inaccessible",
         term: restore_file
       )}
    end
  end

  def ensure_restore_file(other) do
    {:error,
     Error.exception(
       reason: :invalid_restore_file,
       message: "Restore file is invalid or inaccessible",
       term: other
     )}
  end

  # Ensures that the restore operation has been confirmed. Returns :ok if confirmed, otherwise an
  # error with a specific reason.
  def ensure_restore_confirmed(_repo, _repo_config, %{confirm: true}) do
    :ok
  end

  def ensure_restore_confirmed(repo, _repo_config, %{confirm: false}) do
    {:error,
     Error.exception(
       reason: :restore_not_confirmed,
       message: "Restore not confirmed",
       repo: repo
     )}
  end

  def ensure_restore_confirmed(repo, _repo_config, %{confirm: prompt_fun})
      when is_function(prompt_fun, 0) do
    case prompt_fun.() do
      true ->
        :ok

      false ->
        {:error,
         Error.exception(
           reason: :restore_not_confirmed,
           message: "Restore not confirmed",
           repo: repo
         )}

      other ->
        {:error,
         Error.exception(
           reason: :invalid_confirm_function_result,
           message: "Invalid confirmation function result",
           repo: repo,
           term: other
         )}
    end
  end

  def ensure_restore_confirmed(repo, _repo_config, %{confirm: {m, f, a}})
      when is_atom(m) and is_atom(f) and is_list(a) do
    case apply(m, f, a) do
      true ->
        :ok

      false ->
        {:error,
         Error.exception(
           reason: :restore_not_confirmed,
           message: "Restore not confirmed",
           repo: repo
         )}

      other ->
        {:error,
         Error.exception(
           reason: :invalid_confirm_function_result,
           message: "Invalid confirmation function result",
           repo: repo,
           term: other
         )}
    end
  end

  def ensure_restore_confirmed(repo, _repo_config, _options) do
    {:error,
     Error.exception(
       reason: :missing_restore_confirmation,
       message: "Restore not confirmed (missing confirmation)",
       repo: repo
     )}
  end
end
