defmodule EctoBackupTest do
  use ExUnit.Case
  alias EctoBackup.TestRepo
  alias EctoBackup.SecondTestRepo
  alias EctoBackup.StubAdapter

  # TODO: Finish 100% coverage with this test module only

  defmodule InvalidRepoConfig do
    def config(), do: :invalid_config
  end

  def custom_backup_file(_repo, _repo_config, backup_file), do: backup_file
  def custom_restore_file(_repo, _repo_config, restore_file), do: restore_file

  def confirm_restore(_, _, val), do: val

  describe "backup/1" do
    setup do
      backup_dir = StubAdapter.create_backup_dir!()
      {:ok, backup_dir: backup_dir}
    end

    test "can backup using the StubAdapter", %{backup_dir: backup_dir} do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}], backup_dir: backup_dir}
      assert {:ok, [{:ok, TestRepo, backup_file}]} = EctoBackup.backup(opts)
      assert File.exists?(backup_file)

      opts = %{
        repos: [{TestRepo, [adapter: StubAdapter]}, {SecondTestRepo, [adapter: StubAdapter]}],
        backup_dir: backup_dir
      }

      assert {:ok, [{:ok, TestRepo, backup_file}, {:ok, SecondTestRepo, backup_file2}]} =
               EctoBackup.backup(opts)

      assert File.exists?(backup_file)
      assert File.exists?(backup_file2)
    end

    test "can backup with custom backup_file", %{backup_dir: backup_dir} do
      opts_base = %{repos: [{TestRepo, [adapter: StubAdapter]}]}

      custom_backup_file = Path.join(backup_dir, "custom_backup.db")
      opts = Map.put(opts_base, :files, [custom_backup_file])
      assert {:ok, [{:ok, TestRepo, ^custom_backup_file}]} = EctoBackup.backup(opts)
      assert File.exists?(custom_backup_file)

      custom_backup_file = Path.join(backup_dir, "custom_backup.db")
      opts = Map.put(opts_base, :backup_file, custom_backup_file)
      assert {:ok, [{:ok, TestRepo, ^custom_backup_file}]} = EctoBackup.backup(opts)
      assert File.exists?(custom_backup_file)

      custom_backup_file = Path.join(backup_dir, "custom_backup_fn.db")
      fun = fn _repo, _repo_config -> custom_backup_file end
      opts = Map.put(opts_base, :backup_file, fun)
      assert {:ok, [{:ok, TestRepo, ^custom_backup_file}]} = EctoBackup.backup(opts)
      assert File.exists?(custom_backup_file)

      custom_backup_file = Path.join(backup_dir, "custom_backup_mfa.db")
      mfa = {__MODULE__, :custom_backup_file, [custom_backup_file]}
      opts = Map.put(opts_base, :backup_file, mfa)
      assert {:ok, [{:ok, TestRepo, ^custom_backup_file}]} = EctoBackup.backup(opts)
      assert File.exists?(custom_backup_file)
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

    test "returns error for invalid backup repos configurations" do
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

      opts = Map.put(opts, :backup_file, :not_a_binary)
      assert {:error, e} = EctoBackup.backup(opts)
      assert e.reason == :invalid_backup_file

      fun = fn _repo, _repo_config -> :not_a_binary end
      opts = Map.put(opts, :backup_file, fun)
      assert {:error, e} = EctoBackup.backup(opts)
      assert e.reason == :invalid_backup_file

      mfa = {__MODULE__, :custom_backup_file, [:not_a_binary]}
      opts = Map.put(opts, :backup_file, mfa)
      assert {:error, e} = EctoBackup.backup(opts)
      assert e.reason == :invalid_backup_file
    end

    test "returns error for mismatched repos and files lists" do
      opts = %{
        repos: [
          {TestRepo, [adapter: StubAdapter]},
          {SecondTestRepo, [adapter: StubAdapter]}
        ],
        files: ["single_backup_file.db"]
      }

      assert {:error, e} = EctoBackup.backup(opts)
      assert e.reason == :mismatched_backup_file_count
    end

    test "returns error for invalid backup file list" do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}], files: [:invalid_file]}
      assert {:error, e} = EctoBackup.backup(opts)
      assert e.reason == :invalid_backup_file_list
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

  describe "backup!/1" do
    setup do
      backup_dir = StubAdapter.create_backup_dir!()
      {:ok, backup_dir: backup_dir}
    end

    test "can backup using the StubAdapter", %{backup_dir: backup_dir} do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}], backup_dir: backup_dir}
      [{:ok, TestRepo, backup_file}] = EctoBackup.backup!(opts)
      assert File.exists?(backup_file)
    end

    test "can backup using default repo config", %{backup_dir: backup_dir} do
      Application.put_env(:ecto_backup, :repos, [{TestRepo, [adapter: StubAdapter]}])
      Application.put_env(:ecto_backup, :backup_dir, backup_dir)

      assert [{:ok, TestRepo, backup_file}] = EctoBackup.backup!()
      assert File.exists?(backup_file)

      Application.delete_env(:ecto_backup, :repos)
      Application.delete_env(:ecto_backup, :backup_dir)
    end

    test "raises for backup errors", %{backup_dir: backup_dir} do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}]}

      assert_raise EctoBackup.Error, fn ->
        EctoBackup.backup!(opts)
      end

      opts = %{
        repos: [{TestRepo, [adapter: StubAdapter]}],
        backup_file: "invalid_backup_file.db",
        backup_dir: backup_dir
      }

      assert_raise EctoBackup.Error, fn ->
        EctoBackup.backup!(opts)
      end
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

    test "can restore using the StubAdapter", %{backup_dir: backup_dir, backup_file: backup_file} do
      repo_spec = {TestRepo, [adapter: StubAdapter]}

      opts = %{repos: [repo_spec], confirm: [TestRepo], restore_dir: backup_dir}
      assert {:ok, [{:ok, TestRepo, ^backup_file}]} = EctoBackup.restore(opts)

      opts = %{repos: [repo_spec], confirm: fn _, _ -> true end, restore_dir: backup_dir}
      assert {:ok, [{:ok, TestRepo, ^backup_file}]} = EctoBackup.restore(opts)

      opts = %{
        repos: [repo_spec],
        confirm: {__MODULE__, :confirm_restore, [true]},
        restore_dir: backup_dir
      }

      assert {:ok, [{:ok, TestRepo, ^backup_file}]} = EctoBackup.restore(opts)
    end

    test "can restore with custom restore_file", %{backup_dir: backup_dir} do
      # Create a custom backup file
      custom_restore_file = Path.join(backup_dir, "custom_backup.db")
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}], backup_file: custom_restore_file}
      assert {:ok, [{:ok, TestRepo, ^custom_restore_file}]} = EctoBackup.backup(opts)

      opts_base = %{repos: [{TestRepo, [adapter: StubAdapter]}], confirm: [TestRepo]}

      opts = Map.put(opts_base, :files, [custom_restore_file])
      assert {:ok, [{:ok, TestRepo, ^custom_restore_file}]} = EctoBackup.restore(opts)

      opts = Map.put(opts_base, :restore_file, custom_restore_file)
      assert {:ok, [{:ok, TestRepo, ^custom_restore_file}]} = EctoBackup.restore(opts)

      fun = fn _repo, _repo_config -> custom_restore_file end
      opts = Map.put(opts_base, :restore_file, fun)
      assert {:ok, [{:ok, TestRepo, ^custom_restore_file}]} = EctoBackup.restore(opts)

      mfa = {__MODULE__, :custom_restore_file, [custom_restore_file]}
      opts = Map.put(opts_base, :restore_file, mfa)
      assert {:ok, [{:ok, TestRepo, ^custom_restore_file}]} = EctoBackup.restore(opts)
    end

    test "can restore from default repo config", %{backup_file: backup_file} do
      Application.put_env(:ecto_backup, :repos, [
        {TestRepo, [adapter: StubAdapter, restore_file: backup_file]}
      ])

      assert {:ok, [{:ok, TestRepo, ^backup_file}]} = EctoBackup.restore(confirm: [TestRepo])
      Application.delete_env(:ecto_backup, :repos)
    end

    test "can restore with custom restore_dir", %{
      backup_dir: backup_dir,
      backup_file: backup_file
    } do
      opts_base = %{repos: [{TestRepo, [adapter: StubAdapter]}], confirm: [TestRepo]}

      opts = Map.put(opts_base, :restore_dir, backup_dir)
      assert {:ok, [{:ok, TestRepo, ^backup_file}]} = EctoBackup.restore(opts)

      fun = fn _repo, _repo_config -> backup_dir end
      opts = Map.put(opts, :restore_dir, fun)
      assert {:ok, [{:ok, TestRepo, ^backup_file}]} = EctoBackup.restore(opts)

      opts = %{opts | restore_dir: {__MODULE__, :custom_restore_file, [backup_dir]}}
      assert {:ok, [{:ok, TestRepo, ^backup_file}]} = EctoBackup.restore(opts)
    end

    test "returns error when no restore_dir set" do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}]}
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :no_restore_dir_set
    end

    test "returns error for invalid restore repos configurations" do
      assert {:error, e} = EctoBackup.restore(repos: [])
      assert e.reason == :no_repos_to_restore
      assert {:error, e} = EctoBackup.restore()
      assert e.reason == :no_default_repos
      assert {:error, e} = EctoBackup.restore(repos: :invalid)
      assert e.reason == :invalid_repo_list
      Application.put_env(:ecto_backup, :repos, [])
      assert {:error, e} = EctoBackup.restore()
      assert e.reason == :no_repos_to_restore
      Application.put_env(:ecto_backup, :repos, :invalid)
      assert {:error, e} = EctoBackup.restore()
      assert e.reason == :invalid_repo_list
      Application.delete_env(:ecto_backup, :repos)
    end

    test "returns error for invalid restore_file" do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}], confirm: [TestRepo]}

      opts = Map.put(opts, :restore_file, "non_existent_file.db")
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :nonexistent_restore_file

      opts = Map.put(opts, :restore_file, :not_a_binary)
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :invalid_restore_file

      fun = fn _repo, _repo_config -> :not_a_binary end
      opts = Map.put(opts, :restore_file, fun)
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :invalid_restore_file

      mfa = {__MODULE__, :custom_restore_file, [:not_a_binary]}
      opts = Map.put(opts, :restore_file, mfa)
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :invalid_restore_file
    end

    test "returns error for invalid timestamp in restore file name" do
      # Create a new backup dir, backup to a file, then rename it to an invalid timestamp
      backup_dir = StubAdapter.create_backup_dir!()
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}], backup_dir: backup_dir}
      {:ok, [{:ok, TestRepo, backup_file}]} = EctoBackup.backup(opts)

      invalid_restore_name = "ecto_backup_test_repo_backup_2025-01-01T12-34-61Z.db"
      invalid_restore_file = Path.join(backup_dir, invalid_restore_name)
      File.rename!(backup_file, invalid_restore_file)

      opts = %{
        repos: [{TestRepo, [adapter: StubAdapter]}],
        confirm: [TestRepo],
        restore_dir: backup_dir
      }

      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :invalid_restore_file_timestamp
    end

    test "returns error for invalid repos configurations", %{backup_dir: backup_dir} do
      Application.put_env(:ecto_backup, :restore_dir, backup_dir)
      Application.put_env(:ecto_backup, :repos, [])

      assert {:error, e} = EctoBackup.restore()
      assert e.reason == :no_repos_to_restore

      Application.delete_env(:ecto_backup, :repos)
      assert {:error, e} = EctoBackup.restore()
      assert e.reason == :no_default_repos

      Application.delete_env(:ecto_backup, :restore_dir)
    end

    test "returns error when confirmation fails", %{backup_file: backup_file} do
      repo_spec = {TestRepo, [adapter: StubAdapter, restore_file: backup_file]}

      opts = %{repos: [repo_spec]}
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :missing_restore_confirmation

      opts = %{repos: [repo_spec], confirm: false}
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :missing_restore_confirmation

      opts = %{repos: [repo_spec], confirm: []}
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :restore_not_confirmed

      opts = %{repos: [repo_spec], confirm: fn _, _ -> false end}
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :restore_not_confirmed

      opts = %{repos: [repo_spec], confirm: fn _, _ -> :invalid end}
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :invalid_confirm_function_result

      opts = %{repos: [repo_spec], confirm: {__MODULE__, :confirm_restore, [false]}}
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :restore_not_confirmed

      opts = %{repos: [repo_spec], confirm: {__MODULE__, :confirm_restore, [:invalid]}}
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :invalid_confirm_function_result

      Application.put_env(:ecto_backup, :repos, [
        {TestRepo, [adapter: StubAdapter, restore_file: backup_file]}
      ])

      assert {:error, e} = EctoBackup.restore()
      assert e.reason == :missing_restore_confirmation
      Application.delete_env(:ecto_backup, :repos)
    end

    test "returns error for invalid adapter", %{backup_file: backup_file} do
      opts = %{repos: [{TestRepo, [restore_file: backup_file]}], confirm: [TestRepo]}
      assert {:ok, [{:error, TestRepo, e}]} = EctoBackup.restore(opts)
      assert e.reason == :unsupported_ecto_adapter
    end

    test "returns error when restore fails in adapter", %{backup_dir: backup_dir} do
      invalid_file = Path.join(backup_dir, "invalid_restore_file.db")
      File.write!(invalid_file, "invalid data")

      opts = %{
        repos: [{TestRepo, [adapter: StubAdapter, restore_file: invalid_file]}],
        confirm: [TestRepo]
      }

      assert {:ok, [{:error, TestRepo, e}]} = EctoBackup.restore(opts)
      assert e.reason == :invalid_backup_data
    end

    test "returns error for mismatched repos and files lists" do
      opts = %{
        repos: [
          {TestRepo, [adapter: StubAdapter]},
          {SecondTestRepo, [adapter: StubAdapter]}
        ],
        files: ["single_backup_file.db"]
      }

      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :mismatched_restore_file_count
    end

    test "returns error for invalid restore file list" do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}], files: [:invalid_file]}
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :invalid_restore_file_list
    end

    test "returns error for invalid restore_dir" do
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}], confirm: [TestRepo]}

      custom_restore_dir = :invalid_restore_dir
      opts = Map.put(opts, :restore_dir, custom_restore_dir)
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :invalid_restore_dir

      custom_restore_dir = fn _repo, _repo_config -> :invalid_restore_dir end
      opts = Map.put(opts, :restore_dir, custom_restore_dir)
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :invalid_restore_dir

      custom_restore_dir = {__MODULE__, :custom_backup_file, [:invalid_restore_dir]}
      opts = Map.put(opts, :restore_dir, custom_restore_dir)
      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :invalid_restore_dir
    end

    test "returns error when no restore_file found" do
      empty_restore_dir = StubAdapter.create_backup_dir!()

      opts = %{
        repos: [{TestRepo, [adapter: StubAdapter]}],
        restore_dir: empty_restore_dir,
        confirm: [TestRepo]
      }

      assert {:error, e} = EctoBackup.restore(opts)
      assert e.reason == :no_restore_file_found
    end
  end

  describe "restore!/2" do
    setup do
      # Create a stub backup file
      backup_dir = StubAdapter.create_backup_dir!()
      opts = %{repos: [{TestRepo, [adapter: StubAdapter]}], backup_dir: backup_dir}
      {:ok, [{:ok, TestRepo, backup_file}]} = EctoBackup.backup(opts)

      invalid_file = Path.join(backup_dir, "invalid_restore_file.db")
      :ok = File.write(invalid_file, "invalid data")

      {:ok, backup_dir: backup_dir, backup_file: backup_file, invalid_file: invalid_file}
    end

    test "can restore using the StubAdapter", %{backup_file: backup_file} do
      repo_spec = {TestRepo, [adapter: StubAdapter, restore_file: backup_file]}

      assert [{:ok, TestRepo, ^backup_file}] =
               EctoBackup.restore!(repos: [repo_spec], confirm: [TestRepo])
    end

    test "can restore from default repo config", %{backup_file: backup_file} do
      Application.put_env(:ecto_backup, :repos, [
        {TestRepo, [adapter: StubAdapter, restore_file: backup_file]}
      ])

      assert [{:ok, TestRepo, ^backup_file}] = EctoBackup.restore!(confirm: [TestRepo])
      Application.delete_env(:ecto_backup, :repos)
    end

    test "raises for restore errors", %{backup_file: backup_file, invalid_file: invalid_file} do
      repo_spec = {TestRepo, [adapter: StubAdapter, restore_file: backup_file]}

      assert_raise EctoBackup.Error, fn ->
        EctoBackup.restore!(repos: [repo_spec])
      end

      Application.put_env(:ecto_backup, :repos, [
        {TestRepo, [adapter: StubAdapter, restore_file: backup_file]}
      ])

      assert_raise EctoBackup.Error, fn ->
        EctoBackup.restore!()
      end

      Application.delete_env(:ecto_backup, :repos)

      assert_raise EctoBackup.Error, fn ->
        EctoBackup.restore!(
          repos: [repo_spec],
          restore_file: "non_existent_file.db",
          confirm: [TestRepo]
        )
      end

      assert_raise EctoBackup.Error, fn ->
        EctoBackup.restore!(repos: [repo_spec], restore_file: invalid_file, confirm: [TestRepo])
      end
    end
  end
end
