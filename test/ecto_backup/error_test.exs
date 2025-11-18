defmodule EctoBackup.ErrorTest do
  use ExUnit.Case, async: true

  describe "message/1" do
    test "returns explicit message if present" do
      err = %EctoBackup.Error{message: "boom", reason: :ignored, repo: :ignored}
      assert Exception.message(err) == "boom"
    end

    test "formats with reason when repo is nil" do
      err = %EctoBackup.Error{reason: :timeout, repo: nil}
      assert Exception.message(err) == "error :timeout"
    end

    test "formats with reason and repo when repo present" do
      err = %EctoBackup.Error{reason: :connection_error, repo: MyApp.Repo}
      assert Exception.message(err) == "error (:connection_error) for repo MyApp.Repo"
    end
  end

  describe "raise" do
    test "asserts message with repo nil" do
      assert_raise EctoBackup.Error, "error :oops", fn ->
        raise EctoBackup.Error, reason: :oops, repo: nil
      end
    end

    test "asserts explicit message wins over formatting" do
      assert_raise EctoBackup.Error, "boom", fn ->
        raise EctoBackup.Error, message: "boom", reason: :oops, repo: MyApp.Repo
      end
    end
  end
end
