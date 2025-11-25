defmodule EctoBackup.StateTest do
  use ExUnit.Case
  alias EctoBackup.State

  defp unique_key do
    :erlang.unique_integer([:positive]) |> Integer.to_string() |> String.to_atom()
  end

  test "put/get roundtrip" do
    key = unique_key()
    assert State.get(key) == nil
    :ok = State.put(key, :value1)
    assert State.get(key) == :value1
  end

  test "get with default when missing" do
    key = unique_key()
    assert State.get(key, :fallback) == :fallback
  end

  test "fetch success and error" do
    key1 = unique_key()
    key2 = unique_key()
    :ok = State.put(key1, 123)
    assert {:ok, 123} = State.fetch(key1)
    assert :error = State.fetch(key2)
  end

  test "update existing key" do
    key = unique_key()
    :ok = State.put(key, 10)
    :ok = State.update(key, &(&1 + 5))
    assert State.get(key) == 15
  end

  test "update missing key raises" do
    key = unique_key()
    assert_raise ArgumentError, fn -> State.update(key, & &1) end
  end

  test "delete key" do
    key = unique_key()
    :ok = State.put(key, :to_be_deleted)
    assert State.get(key) == :to_be_deleted
    :ok = State.delete(key)
    assert State.get(key) == nil
    assert State.fetch(key) == :error
  end
end
