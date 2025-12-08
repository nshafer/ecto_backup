defmodule EctoBackupTest do
  use ExUnit.Case
  alias EctoBackup.StubAdapter
  alias EctoBackup.TestPGRepo

  describe "backup/1" do
    setup do
      backup_dir = StubAdapter.create_backup_dir!()
      {:ok, backup_dir: backup_dir}
    end

    test "can backup using the StubAdapter", %{backup_dir: backup_dir} do
      opts = %{
        repos: [{TestPGRepo, [adapter: EctoBackup.StubAdapter]}],
        backup_dir: backup_dir
      }

      assert {:ok, [{:ok, TestPGRepo, backup_file}]} = EctoBackup.backup(opts)
      assert File.exists?(backup_file)
    end

    test "can backup using default repo config", %{backup_dir: backup_dir} do
      Application.put_env(:ecto_backup, :repos, [{TestPGRepo, [adapter: EctoBackup.StubAdapter]}])
      Application.put_env(:ecto_backup, :backup_dir, backup_dir)

      assert {:ok, [{:ok, TestPGRepo, backup_file}]} = EctoBackup.backup()
      assert File.exists?(backup_file)

      Application.delete_env(:ecto_backup, :repos)
      Application.delete_env(:ecto_backup, :backup_dir)
    end

    test "returns error for invalid repos configurations" do
      Application.put_env(:ecto_backup, :repos, [])
      assert {:error, e} = EctoBackup.backup()
      assert e.reason == :no_repos_to_backup
      Application.delete_env(:ecto_backup, :repos)
      assert {:error, e} = EctoBackup.backup()
      assert e.reason == :no_default_repos
    end

    test "returns error when backup fails in adapter" do
      opts = %{
        repos: [{TestPGRepo, [adapter: EctoBackup.StubAdapter]}],
        backup_file: "invalid_backup_file.db"
      }

      assert {:ok, [{:error, TestPGRepo, e}]} = EctoBackup.backup(opts)
      assert e.reason == :invalid_backup_file
    end
  end

  describe "restore/2" do
    setup do
      # Create a stub backup file
      backup_dir = StubAdapter.create_backup_dir!()

      {:ok, [{:ok, TestPGRepo, backup_file}]} =
        EctoBackup.backup(%{
          repos: [{TestPGRepo, [adapter: EctoBackup.StubAdapter]}],
          backup_dir: backup_dir
        })

      {:ok, backup_dir: backup_dir, backup_file: backup_file}
    end

    test "can restore using the StubAdapter", %{backup_file: backup_file} do
      repo_spec = {TestPGRepo, [adapter: EctoBackup.StubAdapter]}
      opts = %{repo: repo_spec, confirm: true}
      assert {:ok, TestPGRepo} = EctoBackup.restore(backup_file, opts)
      opts = %{repo: repo_spec, confirm: fn -> true end}
      assert {:ok, TestPGRepo} = EctoBackup.restore(backup_file, opts)
      opts = %{repo: repo_spec, confirm: {__MODULE__, :confirm_restore, [true]}}
      assert {:ok, TestPGRepo} = EctoBackup.restore(backup_file, opts)
    end

    test "can restore from default repo config", %{backup_file: backup_file} do
      Application.put_env(:ecto_backup, :repos, [{TestPGRepo, [adapter: EctoBackup.StubAdapter]}])
      assert {:ok, TestPGRepo} = EctoBackup.restore(backup_file, confirm: true)
      Application.delete_env(:ecto_backup, :repos)
    end

    test "returns error for invalid backup_file" do
      opts = %{repo: {TestPGRepo, [adapter: EctoBackup.StubAdapter]}, confirm: true}
      assert {:error, e} = EctoBackup.restore("non_existent_file.db", opts)
      assert e.reason == :invalid_restore_file
      assert {:error, e} = EctoBackup.restore(:not_a_binary, opts)
      assert e.reason == :invalid_restore_file
    end

    test "returns error for invalid repos configurations" do
      Application.put_env(:ecto_backup, :repos, [])
      assert {:error, e} = EctoBackup.restore("some_file.db", confirm: true)
      assert e.reason == :no_repos_to_restore
      Application.put_env(:ecto_backup, :repos, [TestPGRepo, TestPGRepo])
      assert {:error, e} = EctoBackup.restore("some_file.db", confirm: true)
      assert e.reason == :multiple_repos_to_restore
      Application.delete_env(:ecto_backup, :repos)
      assert {:error, e} = EctoBackup.restore("some_file.db", confirm: true)
      assert e.reason == :no_default_repos
    end

    test "returns error when confirmation fails", %{backup_file: backup_file} do
      repo_spec = {TestPGRepo, [adapter: EctoBackup.StubAdapter]}
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
      Application.put_env(:ecto_backup, :repos, [{TestPGRepo, [adapter: EctoBackup.StubAdapter]}])
      assert {:error, e} = EctoBackup.restore(backup_file)
      assert e.reason == :missing_restore_confirmation
      Application.delete_env(:ecto_backup, :repos)
    end

    test "returns error when restoring invalid data", %{backup_dir: backup_dir} do
      invalid = Path.join(backup_dir, "invalid_backup.db")
      File.write!(invalid, "invalid data")
      opts = %{repo: {TestPGRepo, [adapter: EctoBackup.StubAdapter]}, confirm: true}
      assert {:error, TestPGRepo, :invalid_backup_data} = EctoBackup.restore(invalid, opts)
    end
  end

  def confirm_restore(val) do
    val
  end
end
