defmodule Librarian.Indexer do
  @moduledoc """
  Manages the SQLite FTS5 index for document search and relationship tracking.
  """
  require Logger

  alias Librarian.Repo

  @doc "Index a document into the search database."
  def index_document(attrs) do
    %{
      title: attrs[:title],
      vault_path: attrs[:vault_path],
      library: attrs[:library],
      doc_type: attrs[:doc_type],
      source_file: attrs[:source_file],
      tags: Jason.encode!(attrs[:tags] || []),
      content: attrs[:content] || "",
      checksum: checksum(attrs[:content] || ""),
      created_at: NaiveDateTime.utc_now() |> NaiveDateTime.to_string(),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.to_string()
    }
    |> insert_document()
  end

  @doc "Reindex a file that was modified externally."
  def reindex(vault_path) do
    Logger.info("Reindexing: #{vault_path}")

    case File.read(vault_path) do
      {:ok, content} ->
        update_document_index(vault_path, content)

      {:error, reason} ->
        Logger.warning("Failed to read #{vault_path} for reindex: #{reason}")
    end
  end

  @doc "Search documents using full-text search."
  def search(query) do
    sql = "SELECT title, vault_path, library, tags FROM documents_fts WHERE documents_fts MATCH ?1 ORDER BY rank"
    Repo.query(sql, [query])
  end

  @doc "Add a relationship between two documents."
  def add_relationship(source_path, target_path, rel_type) do
    sql = """
    INSERT INTO relationships (source_id, target_id, rel_type, created_at)
    SELECT s.id, t.id, ?1, datetime('now')
    FROM documents s, documents t
    WHERE s.vault_path = ?2 AND t.vault_path = ?3
    """

    Repo.query(sql, [rel_type, source_path, target_path])
  end

  defp insert_document(attrs) do
    sql = """
    INSERT OR REPLACE INTO documents (title, vault_path, library, doc_type, source_file, tags, checksum, created_at, updated_at)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
    """

    Repo.query(sql, [
      attrs.title,
      attrs.vault_path,
      attrs.library,
      attrs.doc_type,
      attrs.source_file,
      attrs.tags,
      attrs.checksum,
      attrs.created_at,
      attrs.updated_at
    ])
  end

  defp update_document_index(vault_path, content) do
    checksum = checksum(content)

    sql = "UPDATE documents SET content = ?1, checksum = ?2, updated_at = ?3 WHERE vault_path = ?4"

    Repo.query(sql, [
      content,
      checksum,
      NaiveDateTime.utc_now() |> NaiveDateTime.to_string(),
      vault_path
    ])
  end

  defp checksum(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end
end
