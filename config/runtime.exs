import Config

if config_env() == :prod do
  # Parse comma-separated data folders; first value is primary
  data_folders =
    System.fetch_env!("LIBRARIAN_DATA_FOLDER")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

  primary_data_folder = hd(data_folders)

  # Parse comma-separated input paths; always include primary $DATA_FOLDER/input
  extra_inputs =
    case System.get_env("LIBRARIAN_INPUT_PATHS", "") do
      "" -> []
      paths -> paths |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end

  input_paths = [Path.join(primary_data_folder, "input") | extra_inputs] |> Enum.uniq()

  config :librarian, Librarian.Repo,
    database: System.get_env("LIBRARIAN_DB_PATH", "/app/priv/data/librarian.db")

  config :librarian,
    vault_path: System.fetch_env!("LIBRARIAN_VAULT_PATH"),
    data_folder: primary_data_folder,
    data_folders: data_folders,
    input_paths: input_paths,
    log_dir: Path.join(primary_data_folder, "log"),
    notify_webhook_url: System.get_env("LIBRARIAN_NOTIFY_WEBHOOK_URL")
end
