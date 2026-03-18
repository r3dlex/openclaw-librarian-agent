import Config

config :librarian, Librarian.Repo,
  database: System.get_env("LIBRARIAN_DB_PATH", "priv/data/librarian.db")

config :librarian,
  ecto_repos: [Librarian.Repo]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:module]

import_config "#{config_env()}.exs"
