defmodule Librarian.Repo.Migrations.CreateInitialSchema do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE IF NOT EXISTS documents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      vault_path TEXT NOT NULL UNIQUE,
      library TEXT NOT NULL,
      doc_type TEXT NOT NULL,
      source_file TEXT,
      tags TEXT,
      content TEXT,
      checksum TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """

    execute """
    CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
      title, content, tags, library,
      content='documents', content_rowid='id'
    )
    """

    execute """
    CREATE TABLE IF NOT EXISTS relationships (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source_id INTEGER REFERENCES documents(id) ON DELETE CASCADE,
      target_id INTEGER REFERENCES documents(id) ON DELETE CASCADE,
      rel_type TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    """

    execute """
    CREATE TABLE IF NOT EXISTS processing_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source_file TEXT NOT NULL,
      action TEXT NOT NULL,
      destination TEXT,
      library TEXT,
      reasoning TEXT,
      processed_at TEXT NOT NULL
    )
    """

    execute """
    CREATE TABLE IF NOT EXISTS glossary (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      term TEXT NOT NULL,
      definition TEXT NOT NULL,
      library TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """

    execute "CREATE INDEX IF NOT EXISTS idx_documents_library ON documents(library)"
    execute "CREATE INDEX IF NOT EXISTS idx_documents_doc_type ON documents(doc_type)"
    execute "CREATE INDEX IF NOT EXISTS idx_relationships_source ON relationships(source_id)"
    execute "CREATE INDEX IF NOT EXISTS idx_relationships_target ON relationships(target_id)"
    execute "CREATE INDEX IF NOT EXISTS idx_glossary_library ON glossary(library)"
    execute "CREATE INDEX IF NOT EXISTS idx_processing_log_date ON processing_log(processed_at)"
  end

  def down do
    execute "DROP TABLE IF EXISTS glossary"
    execute "DROP TABLE IF EXISTS processing_log"
    execute "DROP TABLE IF EXISTS relationships"
    execute "DROP TABLE IF EXISTS documents_fts"
    execute "DROP TABLE IF EXISTS documents"
  end
end
