import Config

if config_env() == :prod do
  config :librarian, Librarian.Repo,
    database: System.get_env("LIBRARIAN_DB_PATH", "/app/priv/data/librarian.db")

  config :librarian,
    vault_path: System.fetch_env!("LIBRARIAN_VAULT_PATH"),
    data_folder: System.fetch_env!("LIBRARIAN_DATA_FOLDER")
end
