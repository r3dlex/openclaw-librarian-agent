defmodule Librarian.Vault.BackupTest do
  use ExUnit.Case, async: false

  alias Librarian.Vault.Backup

  setup do
    tmp = Path.join(System.tmp_dir!(), "backup_test_#{:rand.uniform(999_999_999)}")
    File.mkdir_p!(tmp)
    Application.put_env(:librarian, :data_folder, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.delete_env(:librarian, :data_folder)
    end)

    %{tmp: tmp, backups_root: Path.join(tmp, "backups")}
  end

  describe "backup/1" do
    test "returns :no_existing_file when source doesn't exist" do
      assert {:ok, :no_existing_file} = Backup.backup("/nonexistent/vault/path.md")
    end

    test "creates a backup copy of an existing file" do
      # Create a source file
      source_dir = System.tmp_dir!()
      source_path = Path.join(source_dir, "backup_source_#{:rand.uniform(999_999)}.md")
      File.write!(source_path, "# Original Content\n\nThis is the file.")

      assert {:ok, backup_path} = Backup.backup(source_path)
      assert File.exists?(backup_path)
      assert File.read!(backup_path) == "# Original Content\n\nThis is the file."

      # Backup filename should contain timestamp and original basename
      backup_name = Path.basename(backup_path)
      source_name = Path.basename(source_path)
      assert String.ends_with?(backup_name, source_name)

      File.rm(source_path)
    end

    test "backup goes into backups/YYYY-MM-DD/ directory" do
      source_path = Path.join(System.tmp_dir!(), "vaultfile_#{:rand.uniform(999_999)}.md")
      File.write!(source_path, "Vault file content")

      assert {:ok, backup_path} = Backup.backup(source_path)

      # The backup path should be under the configured data_folder/backups
      data_folder = Application.get_env(:librarian, :data_folder, "")
      assert String.starts_with?(backup_path, Path.join(data_folder, "backups"))

      File.rm(source_path)
    end

    test "backup preserves file content exactly" do
      content = "# Complex Content\n\n- item 1\n- item 2\n\n```elixir\nIO.puts(\"hello\")\n```"
      source_path = Path.join(System.tmp_dir!(), "complex_#{:rand.uniform(999_999)}.md")
      File.write!(source_path, content)

      assert {:ok, backup_path} = Backup.backup(source_path)
      assert File.read!(backup_path) == content

      File.rm(source_path)
    end
  end

  describe "prune/0" do
    test "does nothing when backups_root does not exist" do
      # data_folder is set but backups dir doesn't exist yet
      assert :ok == (Backup.prune() || :ok)
    end

    test "removes backup directories older than 30 days" do
      backups_root = Path.join(Application.get_env(:librarian, :data_folder), "backups")
      File.mkdir_p!(backups_root)

      # Create an old backup directory (40 days ago)
      old_date = Date.utc_today() |> Date.add(-40) |> Date.to_string()
      old_dir = Path.join(backups_root, old_date)
      File.mkdir_p!(old_dir)
      File.write!(Path.join(old_dir, "backup_file.md"), "old content")

      Backup.prune()

      refute File.dir?(old_dir)
    end

    test "keeps backup directories within the retention period" do
      backups_root = Path.join(Application.get_env(:librarian, :data_folder), "backups")
      File.mkdir_p!(backups_root)

      # Create a recent backup directory (5 days ago)
      recent_date = Date.utc_today() |> Date.add(-5) |> Date.to_string()
      recent_dir = Path.join(backups_root, recent_date)
      File.mkdir_p!(recent_dir)
      File.write!(Path.join(recent_dir, "recent_file.md"), "recent content")

      Backup.prune()

      assert File.dir?(recent_dir)
    end

    test "ignores non-date-named entries in backups_root" do
      backups_root = Path.join(Application.get_env(:librarian, :data_folder), "backups")
      File.mkdir_p!(backups_root)

      # Create a directory with non-date name
      random_dir = Path.join(backups_root, "not-a-date-dir")
      File.mkdir_p!(random_dir)

      Backup.prune()

      # Should not be removed (not matched as a date)
      assert File.dir?(random_dir)
    end
  end
end
