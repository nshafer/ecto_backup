defmodule EctoBackup.UnsupportedAdapter do
  @moduledoc """
  A dummy Ecto.Adapter module to simulate an unsupported database adapter for testing purposes.
  """

  @behaviour Ecto.Adapter

  defmacro __before_compile__(_env) do
    :ok
  end

  def ensure_all_started(_repo, _type) do
    {:ok, []}
  end

  def init(_config) do
    {:ok, [], %{}}
  end

  def checked_out?(_) do
    false
  end

  def checkout(_meta, _config, _fun) do
    :ok
  end

  def loaders(_primitive, _type), do: []
  def dumpers(_primitive, _type), do: []
end
