defmodule Librarian.Repo do
  @moduledoc """
  Ecto repository for the Librarian agent.

  Backed by SQLite via `ecto_sqlite3`. The database path is configured via
  the `:librarian, Librarian.Repo, database:` application environment key,
  which defaults to the `LIBRARIAN_DB_PATH` environment variable.
  """

  use Ecto.Repo,
    otp_app: :librarian,
    adapter: Ecto.Adapters.SQLite3
end
