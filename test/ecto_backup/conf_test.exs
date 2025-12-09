defmodule EctoBackup.ConfTest do
  use ExUnit.Case
  use Patch
  alias EctoBackup.Conf

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
end
