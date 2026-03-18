import Config

if config_env() == :prod do
  data_folder = System.fetch_env!("LIBRARIAN_DATA_FOLDER")

  # Parse comma-separated input paths; always include $DATA_FOLDER/input
  extra_inputs =
    case System.get_env("LIBRARIAN_INPUT_PATHS", "") do
      "" -> []
      paths -> paths |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end

  input_paths = [Path.join(data_folder, "input") | extra_inputs] |> Enum.uniq()

  config :librarian, Librarian.Repo,
    database: System.get_env("LIBRARIAN_DB_PATH", "/app/priv/data/librarian.db")

  config :librarian,
    vault_path: System.fetch_env!("LIBRARIAN_VAULT_PATH"),
    data_folder: data_folder,
    input_paths: input_paths,
    log_dir: Path.join(data_folder, "log")
end
