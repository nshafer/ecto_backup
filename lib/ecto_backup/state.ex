defmodule EctoBackup.State do
  @moduledoc false
  @name __MODULE__

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  ## ETS state storage (mutable, not cleared in tests)

  def fetch(key) do
    case :ets.lookup(@name, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  end

  def get(key, default \\ nil) do
    case :ets.lookup(@name, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end

  def put(key, value) do
    :ets.insert(@name, {key, value})
    :ok
  end

  def update(key, fun) do
    :ets.insert(@name, {key, fun.(:ets.lookup_element(@name, key, 2))})
    :ok
  end

  def delete(key) do
    :ets.delete(@name, key)
    :ok
  end

  ## Callbacks

  @impl true
  def init(:ok) do
    @name = :ets.new(@name, [:public, :set, :named_table, read_concurrency: true])
    {:ok, %{}}
  end
end
