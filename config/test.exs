import Config

config :librarian, Librarian.Repo,
  database: "priv/data/librarian_test.db",
  pool: Ecto.Adapters.SQL.Sandbox

# IAMQ: use a bogus URL so the supervised instance doesn't connect to anything real
config :librarian,
  iamq_url: "http://127.0.0.1:1",
  data_folders: [System.tmp_dir!()]

config :logger, level: :warning
