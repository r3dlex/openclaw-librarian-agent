defmodule Librarian.Application do
  @moduledoc """
  OTP Application for the Librarian agent.

  Supervises: Repo, Vault.Watcher, Input monitor, Reporter, and Archiver.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Librarian.Repo,
      Librarian.Vault.Watcher,
      Librarian.Input,
      Librarian.Reporter,
      Librarian.Archiver
    ]

    opts = [strategy: :one_for_one, name: Librarian.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
