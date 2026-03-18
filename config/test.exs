import Config

config :librarian, Librarian.Repo,
  database: "priv/data/librarian_test.db",
  pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning
