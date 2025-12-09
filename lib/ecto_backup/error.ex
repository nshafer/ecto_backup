defmodule EctoBackup.Error do
  @moduledoc """
  Exception module for EctoBackup errors.
  """
  defexception [:reason, :term, :repo, :message]

  @type t :: %__MODULE__{
          reason: atom(),
          term: term(),
          repo: Ecto.Repo.t() | nil,
          message: String.t() | nil
        }

  @impl true
  def message(%EctoBackup.Error{message: message}) when is_binary(message), do: message

  def message(%EctoBackup.Error{reason: reason, repo: nil}) do
    "error: #{inspect(reason)}"
  end

  def message(%EctoBackup.Error{reason: reason, repo: repo}) do
    "error (#{inspect(repo)}): #{inspect(reason)}"
  end
end
