defmodule EctoBackupTest do
  use ExUnit.Case
  alias EctoBackup.TestRepo
  alias EctoBackup.SecondTestRepo
  alias EctoBackup.StubAdapter

  defmodule InvalidRepoConfig do
    def config(), do: :invalid_config
  end

  def custom_backup_file(_repo, _repo_config, backup_file), do: backup_file

  def confirm_restore(val), do: val

  describe "backup/1" do
    setup do
      backup_dir = StubAdapter.create_backup_dir!()
      {:ok, backup_dir: backup_dir}
    end

    test "can backup using the StubAdapter", %{backup_dir: backup_dir} do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}], backup_dir: backup_dir}
      assert {:ok, [{:ok, TestRepo, backup_file}]} = EctoBackup.backup(opts)
      assert File.exists?(backup_file)
    end

    test "can backup with custom backup_file", %{backup_dir: backup_dir} do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}]}

      custom_backup_file = Path.join(backup_dir, "custom_backup.db")
      opts = Map.put(opts, :backup_file, custom_backup_file)
      assert {:ok, [{:ok, TestRepo, backup_file}]} = EctoBackup.backup(opts)
      assert backup_file == custom_backup_file
      assert File.exists?(backup_file)

      custom_backup_file = Path.join(backup_dir, "custom_backup_fn.db")
      fun = fn _repo, _repo_config -> custom_backup_file end
      opts = Map.put(opts, :backup_file, fun)
      assert {:ok, [{:ok, TestRepo, backup_file}]} = EctoBackup.backup(opts)
      assert backup_file == custom_backup_file
      assert File.exists?(backup_file)

      custom_backup_file = Path.join(backup_dir, "custom_backup_mfa.db")
      opts = %{opts | backup_file: {__MODULE__, :custom_backup_file, [custom_backup_file]}}
      assert {:ok, [{:ok, TestRepo, backup_file}]} = EctoBackup.backup(opts)
      assert backup_file == custom_backup_file
      assert File.exists?(backup_file)
    end

    test "can backup with custom backup_dir" do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}]}

      custom_backup_dir = StubAdapter.create_backup_dir!()
      opts = Map.put(opts, :backup_dir, custom_backup_dir)
      assert {:ok, [{:ok, TestRepo, backup_file}]} = EctoBackup.backup(opts)
      assert File.exists?(backup_file)
      assert String.starts_with?(backup_file, custom_backup_dir)

      custom_backup_dir = StubAdapter.create_backup_dir!()
      fun = fn _repo, _repo_config -> custom_backup_dir end
      opts = Map.put(opts, :backup_dir, fun)
      assert {:ok, [{:ok, TestRepo, backup_file}]} = EctoBackup.backup(opts)
      assert File.exists?(backup_file)
      assert String.starts_with?(backup_file, custom_backup_dir)

      custom_backup_dir = StubAdapter.create_backup_dir!()
      opts = %{opts | backup_dir: {__MODULE__, :custom_backup_file, [custom_backup_dir]}}
      assert {:ok, [{:ok, TestRepo, backup_file}]} = EctoBackup.backup(opts)
      assert File.exists?(backup_file)
      assert String.starts_with?(backup_file, custom_backup_dir)
    end

    test "can backup using default repo config", %{backup_dir: backup_dir} do
      Application.put_env(:ecto_backup, :repos, [{TestRepo, [adapter: StubAdapter]}])
      Application.put_env(:ecto_backup, :backup_dir, backup_dir)

      assert {:ok, [{:ok, TestRepo, backup_file}]} = EctoBackup.backup()
      assert File.exists?(backup_file)

      Application.delete_env(:ecto_backup, :repos)
      Application.delete_env(:ecto_backup, :backup_dir)
    end

    test "returns error when no backup_dir set" do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}]}
      assert {:error, e} = EctoBackup.backup(opts)
      assert e.reason == :no_backup_dir_set
    end

    test "returns error for invalid repos configurations" do
      assert {:error, e} = EctoBackup.backup(repos: [])
      assert e.reason == :no_repos_to_backup
      assert {:error, e} = EctoBackup.backup()
      assert e.reason == :no_default_repos
      assert {:error, e} = EctoBackup.backup(repos: :invalid)
      assert e.reason == :invalid_repo_list
      Application.put_env(:ecto_backup, :repos, [])
      assert {:error, e} = EctoBackup.backup()
      assert e.reason == :no_repos_to_backup
      Application.put_env(:ecto_backup, :repos, :invalid)
      assert {:error, e} = EctoBackup.backup()
      assert e.reason == :invalid_repo_list
      Application.delete_env(:ecto_backup, :repos)
    end

    test "returns error for invalid repo specs" do
      assert {:error, e} = EctoBackup.backup(repos: [123])
      assert e.reason == :invalid_repo_spec
      assert {:error, e} = EctoBackup.backup(repos: [InvalidRepo])
      assert e.reason == :invalid_repo
      assert {:error, e} = EctoBackup.backup(repos: [EctoBackupTest.InvalidRepoConfig])
      assert e.reason == :invalid_repo_config
    end

    test "returns error when backup fails in adapter" do
      opts = %{
        repos: [{TestRepo, [adapter: StubAdapter]}],
        backup_file: "invalid_backup_file.db"
      }

      assert {:ok, [{:error, TestRepo, e}]} = EctoBackup.backup(opts)
      assert e.reason == :invalid_backup_file
    end

    test "raises for unsupported ecto adapter" do
      opts = %{repos: [TestRepo], backup_dir: "/tmp"}
      assert {:ok, [{:error, TestRepo, e}]} = EctoBackup.backup(opts)
      assert e.reason == :unsupported_ecto_adapter
    end

    test "returns error for invalid backup_file" do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}]}

      custom_backup_file = :invalid_backup_file
      opts = Map.put(opts, :backup_file, custom_backup_file)
      assert {:error, e} = EctoBackup.backup(opts)
      assert e.reason == :invalid_backup_file

      custom_backup_file = fn _repo, _repo_config -> :invalid_backup_file end
      opts = Map.put(opts, :backup_file, custom_backup_file)
      assert {:error, e} = EctoBackup.backup(opts)
      assert e.reason == :invalid_backup_file

      custom_backup_file = {__MODULE__, :custom_backup_file, [:invalid_backup_file]}
      opts = Map.put(opts, :backup_file, custom_backup_file)
      assert {:error, e} = EctoBackup.backup(opts)
      assert e.reason == :invalid_backup_file
    end

    test "returns error for invalid backup_dir" do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}]}

      custom_backup_dir = :invalid_backup_dir
      opts = Map.put(opts, :backup_dir, custom_backup_dir)
      assert {:error, e} = EctoBackup.backup(opts)
      assert e.reason == :invalid_backup_dir

      custom_backup_dir = fn _repo, _repo_config -> :invalid_backup_dir end
      opts = Map.put(opts, :backup_dir, custom_backup_dir)
      assert {:error, e} = EctoBackup.backup(opts)
      assert e.reason == :invalid_backup_dir

      custom_backup_dir = {__MODULE__, :custom_backup_file, [:invalid_backup_dir]}
      opts = Map.put(opts, :backup_dir, custom_backup_dir)
      assert {:error, e} = EctoBackup.backup(opts)
      assert e.reason == :invalid_backup_dir
    end
  end

  describe "restore/2" do
    setup do
      # Create a stub backup file
      backup_dir = StubAdapter.create_backup_dir!()
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}], backup_dir: backup_dir}
      {:ok, [{:ok, TestRepo, backup_file}]} = EctoBackup.backup(opts)

      {:ok, backup_dir: backup_dir, backup_file: backup_file}
    end

    test "can restore using the StubAdapter", %{backup_file: backup_file} do
      repo_spec = {TestRepo, [adapter: StubAdapter]}
      opts = %{repo: repo_spec, confirm: true}
      assert {:ok, TestRepo} = EctoBackup.restore(backup_file, opts)
      opts = %{repo: repo_spec, confirm: fn -> true end}
      assert {:ok, TestRepo} = EctoBackup.restore(backup_file, opts)
      opts = %{repo: repo_spec, confirm: {__MODULE__, :confirm_restore, [true]}}
      assert {:ok, TestRepo} = EctoBackup.restore(backup_file, opts)
    end

    test "can restore from default repo config", %{backup_file: backup_file} do
      Application.put_env(:ecto_backup, :repos, [{TestRepo, [adapter: StubAdapter]}])
      assert {:ok, TestRepo} = EctoBackup.restore(backup_file, confirm: true)
      Application.delete_env(:ecto_backup, :repos)
    end

    test "returns error for invalid backup_file" do
      opts = %{repo: {TestRepo, [adapter: StubAdapter]}, confirm: true}
      assert {:error, e} = EctoBackup.restore("non_existent_file.db", opts)
      assert e.reason == :invalid_restore_file
      assert {:error, e} = EctoBackup.restore(:not_a_binary, opts)
      assert e.reason == :invalid_restore_file
    end

    test "returns error for invalid repos configurations" do
      Application.put_env(:ecto_backup, :repos, [])
      assert {:error, e} = EctoBackup.restore("some_file.db", confirm: true)
      assert e.reason == :no_repos_to_restore
      Application.put_env(:ecto_backup, :repos, [TestRepo, SecondTestRepo])
      assert {:error, e} = EctoBackup.restore("some_file.db", confirm: true)
      assert e.reason == :multiple_repos_to_restore
      Application.delete_env(:ecto_backup, :repos)
      assert {:error, e} = EctoBackup.restore("some_file.db", confirm: true)
      assert e.reason == :no_default_repos
    end

    test "returns error when confirmation fails", %{backup_file: backup_file} do
      repo_spec = {TestRepo, [adapter: StubAdapter]}
      opts = %{repo: repo_spec}
      assert {:error, e} = EctoBackup.restore(backup_file, opts)
      assert e.reason == :missing_restore_confirmation
      opts = %{repo: repo_spec, confirm: false}
      assert {:error, e} = EctoBackup.restore(backup_file, opts)
      assert e.reason == :restore_not_confirmed
      opts = %{repo: repo_spec, confirm: fn -> false end}
      assert {:error, e} = EctoBackup.restore(backup_file, opts)
      assert e.reason == :restore_not_confirmed
      opts = %{repo: repo_spec, confirm: fn -> :invalid end}
      assert {:error, e} = EctoBackup.restore(backup_file, opts)
      assert e.reason == :invalid_confirm_function_result
      opts = %{repo: repo_spec, confirm: {__MODULE__, :confirm_restore, [false]}}
      assert {:error, e} = EctoBackup.restore(backup_file, opts)
      assert e.reason == :restore_not_confirmed
      opts = %{repo: repo_spec, confirm: {__MODULE__, :confirm_restore, [:invalid]}}
      assert {:error, e} = EctoBackup.restore(backup_file, opts)
      assert e.reason == :invalid_confirm_function_result
      Application.put_env(:ecto_backup, :repos, [{TestRepo, [adapter: StubAdapter]}])
      assert {:error, e} = EctoBackup.restore(backup_file)
      assert e.reason == :missing_restore_confirmation
      Application.delete_env(:ecto_backup, :repos)
    end

    test "returns error for invalid adapter", %{backup_file: backup_file} do
      opts = %{repo: TestRepo, confirm: true}
      assert {:error, TestRepo, e} = EctoBackup.restore(backup_file, opts)
      assert e.reason == :unsupported_ecto_adapter
    end

    test "returns error when restore fails in adapter" do
      opts = %{repo: {TestRepo, [adapter: StubAdapter]}, confirm: true}
      assert {:error, e} = EctoBackup.restore("invalid_restore_file.db", opts)
      assert e.reason == :invalid_restore_file
    end

    test "returns error from adapter", %{backup_dir: backup_dir} do
      invalid = Path.join(backup_dir, "invalid_backup.db")
      File.write!(invalid, "invalid data")
      opts = %{repo: {TestRepo, [adapter: StubAdapter]}, confirm: true}
      assert {:error, TestRepo, e} = EctoBackup.restore(invalid, opts)
      assert e.reason == :invalid_backup_data
    end
  end
end
