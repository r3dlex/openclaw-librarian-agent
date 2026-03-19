defmodule Librarian.Staging do
  @moduledoc """
  Manages the staging folder — the handoff point between the Elixir service
  and the Librarian agent.

  ## Protocol

  The Elixir service converts documents and writes them to the staging folder.
  The Librarian agent reads from staging, classifies, and files into the vault.

  ### Staging folder structure

      $LIBRARIAN_DATA_FOLDER/staging/
      ├── <uuid>.md              # Converted markdown content
      ├── <uuid>.meta.json       # Metadata for the agent to classify
      └── <uuid>.source          # Original filename reference

  ### Meta file format (JSON)

      {
        "id": "<uuid>",
        "source_file": "quarterly-review.pptx",
        "source_format": ".pptx",
        "converted_at": "2026-03-18T14:30:00Z",
        "byte_size": 4523,
        "instructions": "Convert to meeting minutes, tag as Q1-2026",
        "status": "pending"
      }

  ### Lifecycle

  1. Elixir writes `.md` + `.meta.json` to staging (status: "pending")
  2. Agent reads pending items, classifies, and files into vault
  3. Agent updates `.meta.json` with status: "filed" and destination path
  4. Elixir periodically cleans up "filed" items older than 24 hours
  """
  require Logger

  @doc "Stage a converted document for agent classification."
  def stage(markdown, attrs) do
    staging_dir = staging_dir()
    File.mkdir_p!(staging_dir)

    id = generate_id()
    md_path = Path.join(staging_dir, "#{id}.md")
    meta_path = Path.join(staging_dir, "#{id}.meta.json")

    meta = %{
      id: id,
      source_file: attrs[:source_file] || "unknown",
      source_format: attrs[:source_format] || "",
      converted_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      byte_size: byte_size(markdown),
      instructions: attrs[:instructions],
      status: "pending"
    }

    File.write!(md_path, markdown)
    File.write!(meta_path, Jason.encode!(meta, pretty: true))

    Logger.info("Staged document #{id} from #{meta.source_file}")
    {:ok, id}
  end

  @doc "List all pending items in the staging folder."
  def list_pending do
    staging_dir()
    |> list_by_status("pending")
  end

  @doc "Mark a staged item as filed with its vault destination."
  def mark_filed(id, vault_path) do
    meta_path = Path.join(staging_dir(), "#{id}.meta.json")

    case read_metadata(meta_path) do
      {:ok, existing} ->
        meta =
          existing
          |> Map.merge(%{
            "status" => "filed",
            "vault_path" => vault_path,
            "filed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          })

        File.write!(meta_path, Jason.encode!(meta, pretty: true))
        {:ok, meta}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Clean up filed items older than the retention period (default 24 hours)."
  def cleanup(max_age_hours \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-max_age_hours * 3600)

    staging_dir()
    |> list_by_status("filed")
    |> Enum.filter(fn meta ->
      case DateTime.from_iso8601(meta["filed_at"] || "") do
        {:ok, filed_at, _} -> DateTime.compare(filed_at, cutoff) == :lt
        _ -> false
      end
    end)
    |> Enum.each(fn meta ->
      id = meta["id"]
      dir = staging_dir()

      Enum.each(["#{id}.md", "#{id}.meta.json", "#{id}.source"], fn file ->
        path = Path.join(dir, file)
        if File.exists?(path), do: File.rm!(path)
      end)

      Logger.info("Cleaned up staged item #{id}")
    end)
  end

  defp staging_dir do
    data_folder = Application.get_env(:librarian, :data_folder, "")
    Path.join(data_folder, "staging")
  end

  defp list_by_status(dir, status) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".meta.json"))
      |> Enum.flat_map(fn file ->
        path = Path.join(dir, file)

        case read_metadata(path) do
          {:ok, meta} ->
            if meta["status"] == status, do: [meta], else: []

          {:error, reason} ->
            Logger.warning("Corrupt staging metadata #{file}: #{inspect(reason)}, removing")
            File.rm(path)
            md_path = Path.join(dir, String.replace_suffix(file, ".meta.json", ".md"))
            if File.exists?(md_path), do: File.rm(md_path)
            []
        end
      end)
    else
      []
    end
  end

  defp read_metadata(path) do
    case File.read(path) do
      {:ok, content} when content != "" ->
        case Jason.decode(content) do
          {:ok, meta} -> {:ok, meta}
          {:error, reason} -> {:error, reason}
        end

      {:ok, _empty} ->
        {:error, :empty_file}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
