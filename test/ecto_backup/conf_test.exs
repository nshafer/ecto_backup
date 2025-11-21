defmodule EctoBackup.ConfTest do
  use ExUnit.Case
  use Patch
  alias EctoBackup.TestPGRepo
  alias EctoBackup.Conf
  alias EctoBackup.ConfError

  doctest EctoBackup.Conf

  defmodule InvalidRepo do
    def __adapter__, do: Ecto.Adapters.Postgres
    def config, do: nil
  end

  def backup_file_fun(_repo, _repo_config, path) do
    path
  end

  def raise_err(_repo, _repo_config) do
    raise "Intentional exception for testing"
  end

  describe "fetch/3" do
    test "fetches values from the given options" do
      Application.put_env(:ecto_backup, :foo, "no")
      assert {:ok, "bar"} = Conf.fetch(%{foo: "no"}, %{foo: "bar"}, :foo)
      Application.delete_env(:ecto_backup, :foo)
    end

    test "fetches values from repo config" do
      Application.put_env(:ecto_backup, :foo, "no")
      assert {:ok, "bar"} = Conf.fetch(%{foo: "bar"}, %{}, :foo)
      Application.delete_env(:ecto_backup, :foo)
    end

    test "fetches values from :ecto_backup env" do
      Application.put_env(:ecto_backup, :foo, "bar")
      assert {:ok, "bar"} = Conf.fetch(%{}, %{}, :foo)
      Application.delete_env(:ecto_backup, :foo)
    end
  end

  describe "fetch!/3" do
    test "fetches values or raises" do
      assert "bar" = Conf.fetch!(%{foo: "bar"}, %{}, :foo)

      assert_raise KeyError, ~r/key :foo not found/, fn ->
        Conf.fetch!(%{}, %{}, :foo)
      end
    end
  end

  describe "get/4" do
    test "gets values or returns default" do
      assert "bar" = Conf.get(%{foo: "bar"}, %{}, :foo, "default")
      assert "default" = Conf.get(%{}, %{}, :foo, "default")
    end
  end

  describe "get_repo_configs/1" do
    setup do
      Application.put_env(:ecto_backup, :ecto_repos, [TestPGRepo])
      on_exit(fn -> Application.delete_env(:ecto_backup, :ecto_repos) end)
      :ok
    end

    test "can override repo configuration with application env" do
      Application.put_env(:ecto_backup, TestPGRepo,
        username: "app_user",
        password: "app_pass"
      )

      assert {:ok, [{TestPGRepo, repo_config}]} = Conf.get_repo_configs([])
      assert repo_config[:hostname] == "localhost"
      assert repo_config[:database] == "ecto_backup_test"
      assert repo_config[:username] == "app_user"
      assert repo_config[:password] == "app_pass"
      Application.delete_env(:ecto_backup, TestPGRepo)
    end

    test "can override repo configuration with options" do
      overrides = [username: "override_user", password: "override_pass"]
      assert {:ok, [{TestPGRepo, repo_config}]} = Conf.get_repo_configs([{TestPGRepo, overrides}])
      assert repo_config[:hostname] == "localhost"
      assert repo_config[:database] == "ecto_backup_test"
      assert repo_config[:username] == "override_user"
      assert repo_config[:password] == "override_pass"
    end

    test "returns error when no default repos are found" do
      Application.delete_env(:ecto_backup, :ecto_repos)
      assert {:error, e} = Conf.get_repo_configs([])
      assert %ConfError{reason: :no_default_repos_in_mix} = e
      assert Exception.message(e) =~ "no default repositories found"
    end

    test "returns error on invalid repo specification" do
      assert {:error, e} = Conf.get_repo_configs([123])
      assert %ConfError{reason: :invalid_repo_spec} = e
      assert Exception.message(e) =~ "invalid repo specification"
    end

    test "returns error on invalid repo" do
      assert {:error, e} = Conf.get_repo_configs([ConfTest])
      assert %ConfError{reason: :invalid_repo} = e
      assert Exception.message(e) =~ "is not a valid Ecto.Repo module"
    end

    test "returns error when repo config is invalid" do
      assert {:error, e} = Conf.get_repo_configs([InvalidRepo])
      assert %ConfError{reason: :invalid_repo_config} = e
      assert Exception.message(e) =~ "invalid repo config returned from"
    end
  end

  describe "get_default_repos/0" do
    test "returns repos from :ecto_backup config" do
      Application.put_env(:ecto_backup, :ecto_repos, [TestPGRepo])
      assert {:ok, repos} = Conf.get_default_repos()
      assert repos == [TestPGRepo]
      Application.delete_env(:ecto_backup, :ecto_repos)
    end

    test "returns repos from Mix project when available" do
      patch(Mix.Project, :config, fn -> [app: :ecto_backup_test] end)
      Application.put_env(:ecto_backup_test, :ecto_repos, [TestPGRepo])
      assert {:ok, repos} = Conf.get_default_repos()
      assert repos == [TestPGRepo]
      Application.delete_env(:ecto_backup_test, :ecto_repos)
    end

    test "returns repos from umbrella Mix project when available" do
      patch(Mix.Project, :config, fn -> [apps_path: "apps"] end)
      patch(Mix.Project, :apps_paths, fn -> %{test_app: "apps/test_app"} end)
      patch(Mix.Project, :deps_apps, fn -> [:test_app] end)
      Application.put_env(:test_app, :ecto_repos, [TestPGRepo])
      assert {:ok, repos} = Conf.get_default_repos()
      assert repos == [TestPGRepo]
      Application.delete_env(:test_app, :ecto_repos)
    end

    test "returns error when no repos found" do
      patch(Mix.Project, :config, fn -> [app: :ecto_backup_test] end)
      assert {:error, %ConfError{reason: :no_default_repos_in_mix}} = Conf.get_default_repos()
    end
  end

  describe "get_backup_file!/3" do
    test "returns backup file from options" do
      backup_file = "/path/to/backup.db"
      assert ^backup_file = Conf.get_backup_file!(TestPGRepo, %{}, %{backup_file: backup_file})
    end

    test "returns backup file from repo config" do
      backup_file = "/path/to/backup.db"
      assert ^backup_file = Conf.get_backup_file!(TestPGRepo, %{backup_file: backup_file}, %{})
    end

    test "returns backup file from application env" do
      backup_file = "/path/to/backup.db"
      Application.put_env(:ecto_backup, :backup_file, backup_file)
      assert ^backup_file = Conf.get_backup_file!(TestPGRepo, %{}, %{})
      Application.delete_env(:ecto_backup, :backup_file)
    end

    test "can return backup file from function" do
      backup_file = "/path/to/backup.db"
      fun = fn _repo, _config -> backup_file end
      assert ^backup_file = Conf.get_backup_file!(TestPGRepo, %{backup_file: fun}, %{})
    end

    test "raises error when backup_file function returns invalid value" do
      fun = fn _repo, _config -> 123 end

      assert_raise ConfError, ~r/invalid backup file path/, fn ->
        Conf.get_backup_file!(TestPGRepo, %{backup_file: fun}, %{})
      end
    end

    test "can return backup file from mfa tuple" do
      backup_file = "/path/to/backup.db"
      mfa = {__MODULE__, :backup_file_fun, [backup_file]}
      assert ^backup_file = Conf.get_backup_file!(TestPGRepo, %{backup_file: mfa}, %{})
    end

    test "raises error when backup_file mfa returns invalid value" do
      mfa = {__MODULE__, :backup_file_fun, [123]}

      assert_raise ConfError, ~r/invalid backup file path/, fn ->
        Conf.get_backup_file!(TestPGRepo, %{backup_file: mfa}, %{})
      end
    end

    test "returns default backup file when not specified" do
      assert backup_file = Conf.get_backup_file!(TestPGRepo, %{}, %{backup_dir: "/tmp/backups"})
      assert String.starts_with?(backup_file, "/tmp/backups/ecto_backup_test_pg_repo_backup_")
      assert String.ends_with?(backup_file, ".db")
    end

    test "raises error when given invalid backup_file" do
      assert_raise ConfError, ~r/invalid backup file path/, fn ->
        Conf.get_backup_file!(TestPGRepo, %{}, %{backup_file: 123})
      end
    end

    test "throws error if nil backup_dir given" do
      assert_raise ConfError, ~r/invalid backup directory path/, fn ->
        Conf.get_backup_file!(TestPGRepo, %{}, %{backup_dir: nil})
      end
    end

    test "raises error when backup_file function raises exception" do
      fun = fn _repo, _config -> raise "Intentional exception for testing" end

      assert_raise RuntimeError, "Intentional exception for testing", fn ->
        Conf.get_backup_file!(TestPGRepo, %{backup_file: fun}, %{})
      end
    end

    test "raises error when backup_file mfa raises exception" do
      mfa = {__MODULE__, :raise_err, []}

      assert_raise RuntimeError, "Intentional exception for testing", fn ->
        Conf.get_backup_file!(TestPGRepo, %{backup_file: mfa}, %{})
      end
    end
  end

  describe "get_backup_files/2" do
    test "returns list of backup files for repo configs" do
      assert {:ok, repo_configs} = Conf.get_repo_configs([TestPGRepo])
      options = %{backup_dir: "/tmp/backups"}
      assert {:ok, [backup_file]} = Conf.get_backup_files(repo_configs, options)
      assert String.starts_with?(backup_file, "/tmp/backups/ecto_backup_test_pg_repo_backup_")
      assert String.ends_with?(backup_file, ".db")
    end

    test "returns error if any repo config has invalid backup file" do
      assert {:ok, [{TestPGRepo, repo_config}]} = Conf.get_repo_configs([TestPGRepo])
      invalid_repo_config = Map.put(repo_config, :backup_file, 123)
      repo_configs = [{TestPGRepo, invalid_repo_config}]

      assert {:error, e} = Conf.get_backup_files(repo_configs, %{})
      assert %ConfError{reason: :invalid_backup_file} = e
      assert Exception.message(e) =~ "invalid backup file path"
    end

    test "returns error if no backup_dir set and no backup_file specified" do
      assert {:ok, [{TestPGRepo, repo_config}]} = Conf.get_repo_configs([TestPGRepo])
      repo_configs = [{TestPGRepo, repo_config}]

      assert {:error, e} = Conf.get_backup_files(repo_configs, %{})
      assert %ConfError{reason: :no_backup_dir_set} = e
      assert Exception.message(e) =~ "no backup directory is set"
    end
  end

  describe "get_backup_dir!/3" do
    test "returns backup_dir from options" do
      backup_dir = "/custom/backup/dir"
      assert ^backup_dir = Conf.get_backup_dir!(TestPGRepo, %{}, %{backup_dir: backup_dir})
    end

    test "returns backup_dir from repo config" do
      backup_dir = "/custom/backup/dir"
      assert ^backup_dir = Conf.get_backup_dir!(TestPGRepo, %{backup_dir: backup_dir}, %{})
    end

    test "returns backup_dir from application env" do
      backup_dir = "/custom/backup/dir"
      Application.put_env(:ecto_backup, :backup_dir, backup_dir)
      assert ^backup_dir = Conf.get_backup_dir!(TestPGRepo, %{}, %{})
      Application.delete_env(:ecto_backup, :backup_dir)
    end

    test "can return backup dir from function" do
      backup_dir = "/custom/backup/dir"
      fun = fn _repo, _config -> backup_dir end
      assert ^backup_dir = Conf.get_backup_dir!(TestPGRepo, %{backup_dir: fun}, %{})
    end

    test "raises error when backup_dir function returns invalid value" do
      fun = fn _repo, _config -> 123 end

      assert_raise ConfError, ~r/invalid backup directory path/, fn ->
        Conf.get_backup_dir!(TestPGRepo, %{backup_dir: fun}, %{})
      end
    end

    test "can return backup dir from mfa tuple" do
      backup_dir = "/custom/backup/dir"
      mfa = {__MODULE__, :backup_file_fun, [backup_dir]}
      assert ^backup_dir = Conf.get_backup_dir!(TestPGRepo, %{backup_dir: mfa}, %{})
    end

    test "raises error when backup_dir mfa returns invalid value" do
      mfa = {__MODULE__, :backup_file_fun, [123]}

      assert_raise ConfError, ~r/invalid backup directory path/, fn ->
        Conf.get_backup_dir!(TestPGRepo, %{backup_dir: mfa}, %{})
      end
    end

    test "raises error when given invalid backup_dir" do
      assert_raise ConfError, ~r/invalid backup directory path/, fn ->
        Conf.get_backup_dir!(TestPGRepo, %{}, %{backup_dir: 123})
      end
    end

    test "raises error when no backup_dir found" do
      assert_raise ConfError, ~r/no backup directory is set/, fn ->
        Conf.get_backup_dir!(TestPGRepo, %{}, %{})
      end
    end
  end
end
