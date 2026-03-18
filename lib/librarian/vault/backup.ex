defmodule Librarian.Vault.Backup do
  @moduledoc """
  Creates backups of vault files before overwriting them.

  Backups are stored in $LIBRARIAN_DATA_FOLDER/backups/ with a timestamped
  directory structure. Old backups are pruned after a configurable retention
  period (default: 30 days).
  """
  require Logger

  @retention_days 30

  @doc """
  Back up a file before overwriting it. Returns {:ok, backup_path} or {:error, reason}.
  """
  def backup(vault_path) do
    if File.exists?(vault_path) do
      backup_dir = backup_dir_for(vault_path)
      File.mkdir_p!(backup_dir)

      timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d_%H%M%S")
      basename = Path.basename(vault_path)
      backup_path = Path.join(backup_dir, "#{timestamp}_#{basename}")

      case File.cp(vault_path, backup_path) do
        :ok ->
          Logger.info("Backed up #{vault_path} → #{backup_path}")
          {:ok, backup_path}

        {:error, reason} ->
          Logger.error("Backup failed for #{vault_path}: #{reason}")
          {:error, reason}
      end
    else
      {:ok, :no_existing_file}
    end
  end

  @doc """
  Prune backups older than the retention period.
  """
  def prune do
    backups_root = backups_root()

    if File.dir?(backups_root) do
      cutoff = Date.utc_today() |> Date.add(-@retention_days)

      backups_root
      |> File.ls!()
      |> Enum.filter(fn entry ->
        case Date.from_iso8601(entry) do
          {:ok, date} -> Date.compare(date, cutoff) == :lt
          _ -> false
        end
      end)
      |> Enum.each(fn dir ->
        path = Path.join(backups_root, dir)
        File.rm_rf!(path)
        Logger.info("Pruned old backup directory: #{path}")
      end)
    end
  end

  defp backup_dir_for(_vault_path) do
    date = Date.utc_today() |> Date.to_string()
    Path.join(backups_root(), date)
  end

  defp backups_root do
    data_folder = Application.get_env(:librarian, :data_folder, "")
    Path.join(data_folder, "backups")
  end
end
