defmodule Librarian.StagingTest do
  use ExUnit.Case, async: false

  alias Librarian.Staging

  setup do
    # Use a unique temp directory for each test
    tmp = Path.join(System.tmp_dir!(), "staging_test_#{:rand.uniform(999_999_999)}")
    File.mkdir_p!(tmp)
    Application.put_env(:librarian, :data_folder, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.delete_env(:librarian, :data_folder)
    end)

    %{tmp: tmp, staging_dir: Path.join(tmp, "staging")}
  end

  describe "stage/2" do
    test "stages a new document and returns an id", %{staging_dir: staging_dir} do
      assert {:ok, id} =
               Staging.stage("# Hello\n\nSome content", %{
                 source_file: "test.docx",
                 source_format: ".docx"
               })

      assert is_binary(id)

      # md and meta files should exist
      assert File.exists?(Path.join(staging_dir, "#{id}.md"))
      assert File.exists?(Path.join(staging_dir, "#{id}.meta.json"))

      meta_content = File.read!(Path.join(staging_dir, "#{id}.meta.json"))
      meta = Jason.decode!(meta_content)

      assert meta["id"] == id
      assert meta["source_file"] == "test.docx"
      assert meta["source_format"] == ".docx"
      assert meta["status"] == "pending"
      assert is_binary(meta["checksum"])
      assert is_integer(meta["byte_size"])
    end

    test "deduplicates identical content returns existing id" do
      content = "# Duplicate content\n\nSame text."

      assert {:ok, id1} =
               Staging.stage(content, %{source_file: "file1.docx", source_format: ".docx"})

      assert {:ok, id2} =
               Staging.stage(content, %{source_file: "file2.docx", source_format: ".docx"})

      assert id1 == id2
    end

    test "stages different content as separate items" do
      assert {:ok, id1} =
               Staging.stage("Content A", %{source_file: "a.txt", source_format: ".txt"})

      assert {:ok, id2} =
               Staging.stage("Content B", %{source_file: "b.txt", source_format: ".txt"})

      assert id1 != id2
    end

    test "stores instructions in meta" do
      instructions = "Please tag as Q1 report"

      assert {:ok, id} =
               Staging.stage("Some content", %{
                 source_file: "report.docx",
                 source_format: ".docx",
                 instructions: instructions
               })

      meta_path = Path.join([Application.get_env(:librarian, :data_folder), "staging", "#{id}.meta.json"])
      meta = Jason.decode!(File.read!(meta_path))
      assert meta["instructions"] == instructions
    end

    test "defaults source_file to 'unknown' when not provided" do
      assert {:ok, id} = Staging.stage("Hello world", %{})

      meta_path = Path.join([Application.get_env(:librarian, :data_folder), "staging", "#{id}.meta.json"])
      meta = Jason.decode!(File.read!(meta_path))
      assert meta["source_file"] == "unknown"
    end
  end

  describe "list_pending/0" do
    test "returns empty list when staging dir doesn't exist" do
      Application.put_env(:librarian, :data_folder, "/nonexistent/path")
      assert Staging.list_pending() == []
    end

    test "returns list of pending items" do
      assert {:ok, _id1} = Staging.stage("Content 1", %{source_file: "a.docx"})
      assert {:ok, _id2} = Staging.stage("Content 2", %{source_file: "b.docx"})

      pending = Staging.list_pending()
      assert length(pending) == 2
      assert Enum.all?(pending, fn m -> m["status"] == "pending" end)
    end

    test "does not return filed items" do
      assert {:ok, id} = Staging.stage("Content", %{source_file: "a.docx"})
      Staging.mark_filed(id, "/vault/path/to/doc.md")

      pending = Staging.list_pending()
      assert Enum.all?(pending, fn m -> m["id"] != id end)
    end
  end

  describe "mark_filed/2" do
    test "marks an item as filed with vault path" do
      assert {:ok, id} = Staging.stage("Some content", %{source_file: "doc.md"})
      vault_path = "/vault/project/doc.md"

      assert {:ok, meta} = Staging.mark_filed(id, vault_path)
      assert meta["status"] == "filed"
      assert meta["vault_path"] == vault_path
      assert is_binary(meta["filed_at"])
    end

    test "returns error for non-existent id" do
      assert {:error, _reason} = Staging.mark_filed("nonexistent_id", "/vault/path.md")
    end
  end

  describe "cleanup/1" do
    test "removes filed items older than max_age_hours" do
      assert {:ok, id} = Staging.stage("Content", %{source_file: "doc.md"})

      staging_dir = Path.join(Application.get_env(:librarian, :data_folder), "staging")
      meta_path = Path.join(staging_dir, "#{id}.meta.json")
      meta = Jason.decode!(File.read!(meta_path))

      # Write a past filed_at timestamp (48 hours ago)
      old_time = DateTime.utc_now() |> DateTime.add(-48 * 3600) |> DateTime.to_iso8601()

      updated_meta =
        Map.merge(meta, %{
          "status" => "filed",
          "vault_path" => "/vault/doc.md",
          "filed_at" => old_time
        })

      File.write!(meta_path, Jason.encode!(updated_meta, pretty: true))

      Staging.cleanup(24)

      # Files should be removed
      refute File.exists?(Path.join(staging_dir, "#{id}.md"))
      refute File.exists?(meta_path)
    end

    test "keeps filed items within the retention period" do
      assert {:ok, id} = Staging.stage("Content", %{source_file: "doc.md"})

      staging_dir = Path.join(Application.get_env(:librarian, :data_folder), "staging")
      meta_path = Path.join(staging_dir, "#{id}.meta.json")

      # Mark filed with recent timestamp
      {:ok, _} = Staging.mark_filed(id, "/vault/doc.md")

      Staging.cleanup(24)

      # Files should still exist (filed recently)
      assert File.exists?(meta_path)
    end

    test "does not remove pending items" do
      assert {:ok, id} = Staging.stage("Content", %{source_file: "doc.md"})

      staging_dir = Path.join(Application.get_env(:librarian, :data_folder), "staging")
      Staging.cleanup(0)

      # Pending item should still exist
      assert File.exists?(Path.join(staging_dir, "#{id}.meta.json"))
    end
  end

  describe "deep_cleanup/0" do
    test "returns :ok (Logger.debug) when staging directory does not exist" do
      Application.put_env(:librarian, :data_folder, "/nonexistent/path/for/deep_cleanup")
      # deep_cleanup logs a debug message and returns :ok when the staging dir is missing
      result = Staging.deep_cleanup()
      assert result == :ok
    end

    test "removes all filed items" do
      assert {:ok, id1} = Staging.stage("Filed content", %{source_file: "filed.md"})
      assert {:ok, _id2} = Staging.stage("Pending content", %{source_file: "pending.md"})

      Staging.mark_filed(id1, "/vault/filed.md")

      staging_dir = Path.join(Application.get_env(:librarian, :data_folder), "staging")
      result = Staging.deep_cleanup()

      assert result >= 1
      # Filed item should be gone
      refute File.exists?(Path.join(staging_dir, "#{id1}.md"))
      refute File.exists?(Path.join(staging_dir, "#{id1}.meta.json"))
    end

    test "removes orphaned .md files without meta" do
      staging_dir = Path.join(Application.get_env(:librarian, :data_folder), "staging")
      File.mkdir_p!(staging_dir)

      # Create orphaned .md file (no corresponding .meta.json)
      orphan_id = "orphaned_md_test_123"
      File.write!(Path.join(staging_dir, "#{orphan_id}.md"), "Orphaned content")

      Staging.deep_cleanup()

      refute File.exists?(Path.join(staging_dir, "#{orphan_id}.md"))
    end

    test "removes orphaned .meta.json files without .md" do
      staging_dir = Path.join(Application.get_env(:librarian, :data_folder), "staging")
      File.mkdir_p!(staging_dir)

      # Create orphaned .meta.json file (no corresponding .md)
      orphan_id = "orphaned_meta_test_456"
      meta = %{"id" => orphan_id, "status" => "pending", "source_file" => "gone.md"}
      File.write!(Path.join(staging_dir, "#{orphan_id}.meta.json"), Jason.encode!(meta))

      Staging.deep_cleanup()

      refute File.exists?(Path.join(staging_dir, "#{orphan_id}.meta.json"))
    end

    test "removes stale pending items older than 48 hours" do
      assert {:ok, id} = Staging.stage("Stale content", %{source_file: "stale.md"})

      staging_dir = Path.join(Application.get_env(:librarian, :data_folder), "staging")
      meta_path = Path.join(staging_dir, "#{id}.meta.json")
      meta = Jason.decode!(File.read!(meta_path))

      # Backdate converted_at to 72 hours ago
      old_time = DateTime.utc_now() |> DateTime.add(-72 * 3600) |> DateTime.to_iso8601()
      updated_meta = Map.put(meta, "converted_at", old_time)
      File.write!(meta_path, Jason.encode!(updated_meta))

      Staging.deep_cleanup()

      refute File.exists?(Path.join(staging_dir, "#{id}.md"))
      refute File.exists?(meta_path)
    end
  end
end
