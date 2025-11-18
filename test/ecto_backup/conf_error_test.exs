defmodule EctoBackup.ConfErrorTest do
  use ExUnit.Case, async: true

  describe "message/1" do
    test "returns explicit message if present" do
      err = %EctoBackup.ConfError{message: "boom", reason: :ignored}
      assert Exception.message(err) == "boom"
    end

    test "no_default_repos_in_mix contains helpful guidance" do
      err = %EctoBackup.ConfError{reason: :no_default_repos_in_mix}
      msg = Exception.message(err)
      assert String.contains?(msg, "no default repositories found")
      assert String.contains?(msg, "ecto_repos")
      assert String.contains?(msg, "config :ecto_backup, ecto_repos: [MyApp.Repo]")
    end

    test "no_default_repos contains Mix-unavailable guidance" do
      err = %EctoBackup.ConfError{reason: :no_default_repos}
      msg = Exception.message(err)
      assert String.contains?(msg, "no default repositories found")
      assert String.contains?(msg, "Mix is not available")
      assert String.contains?(msg, "config :ecto_backup, ecto_repos: [MyApp.Repo]")
    end

    test "invalid_repo_spec formats value" do
      err = %EctoBackup.ConfError{reason: :invalid_repo_spec, value: 123}

      assert Exception.message(err) ==
               "invalid repo specification, expected atom or {atom, keyword}, got: 123"
    end

    test "invalid_repo_config formats repo and config" do
      err = %EctoBackup.ConfError{
        reason: :invalid_repo_config,
        repo: MyApp.Repo,
        value: [bad: :config]
      }

      assert Exception.message(err) ==
               "invalid repo config returned from MyApp.Repo.config/0, got: [bad: :config]"
    end

    test "invalid_repo formats repo" do
      err = %EctoBackup.ConfError{reason: :invalid_repo, repo: NotARepo}
      assert Exception.message(err) == "NotARepo is not a valid Ecto.Repo module"
    end

    test "invalid_backup_file formats invalid value" do
      err = %EctoBackup.ConfError{reason: :invalid_backup_file, value: :not_a_string}

      assert Exception.message(err) ==
               "invalid backup file path, expected a string, got :not_a_string"
    end

    test "invalid_backup_dir formats invalid value" do
      err = %EctoBackup.ConfError{reason: :invalid_backup_dir, value: %{}}

      assert Exception.message(err) ==
               "invalid backup directory path, expected a string, got %{}"
    end

    test "no_backup_dir_set contains guidance" do
      err = %EctoBackup.ConfError{reason: :no_backup_dir_set}
      msg = Exception.message(err)
      assert String.contains?(msg, "no backup directory is set")
      assert String.contains?(msg, "config :ecto_backup, backup_dir:")
    end
  end

  describe "raise" do
    test "explicit message wins when raising" do
      assert_raise EctoBackup.ConfError, "boom", fn ->
        raise EctoBackup.ConfError, message: "boom", reason: :invalid_repo
      end
    end

    test "raising invalid_repo_spec yields expected single-line message" do
      assert_raise EctoBackup.ConfError,
                   "invalid repo specification, expected atom or {atom, keyword}, got: :bad",
                   fn ->
                     raise EctoBackup.ConfError, reason: :invalid_repo_spec, value: :bad
                   end
    end
  end
end
