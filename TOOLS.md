# Tools

Environment-specific configuration for this Librarian instance.
Skills define *how* tools work. This file captures *your* setup.

## Paths

All paths are configured via environment variables in `.env`:

- **Vault**: `$LIBRARIAN_VAULT_PATH` — The Obsidian vault root. All organized documents live here.
- **Data folder**: `$LIBRARIAN_DATA_FOLDER` — Working directory containing `input/`, `logs/`, `backups/`, and runtime data.
- **Database**: `$LIBRARIAN_DB_PATH` — SQLite index. Defaults to `$LIBRARIAN_DATA_FOLDER/librarian.db`.
- **Backups**: `$LIBRARIAN_DATA_FOLDER/backups/` — Timestamped backups of vault files before overwrite. Pruned after 30 days.

## Document Processing Pipeline

Format conversion uses Pandoc (available in the Docker container):

| Input Format | Command |
|-------------|---------|
| `.docx` | `pandoc -f docx -t markdown --wrap=none` |
| `.pptx` | `pandoc -f pptx -t markdown --wrap=none` |
| `.txt` | Direct copy (already plaintext) |
| `.pdf` | `pandoc -f pdf -t markdown` (or OCR fallback) |
| `.md` | Direct copy |
| Images | Extract text via OCR, store original in vault `assets/` |

## Services

The Elixir application provides these services (accessible via Mix tasks or IEx):

- `Librarian.Vault.Watcher` — Filesystem change detection
- `Librarian.Vault.Backup` — File backup before overwrite (30-day retention, daily pruning)
- `Librarian.Processor` — Document conversion and classification
- `Librarian.Indexer` — SQLite FTS5 indexing and search
- `Librarian.Reporter` — Daily report generation + backup pruning
