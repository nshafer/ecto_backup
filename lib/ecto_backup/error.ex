defmodule EctoBackup.Error do
  defexception [:reason, :term, :repo, :message]

  @impl true
  def message(%EctoBackup.Error{message: message}) when is_binary(message), do: message

  def message(%EctoBackup.Error{reason: reason, repo: nil}) do
    "error #{inspect(reason)}"
  end

  def message(%EctoBackup.Error{reason: reason, repo: repo}) do
    "error (#{inspect(reason)}) for repo #{inspect(repo)}"
  end
end
