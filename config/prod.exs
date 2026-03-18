import Config

config :logger, level: String.to_atom(System.get_env("LIBRARIAN_LOG_LEVEL", "info"))
