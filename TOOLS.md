# Tools

Environment-specific configuration for this Librarian instance.
Skills define *how* tools work. This file captures *your* setup.

## Paths

All paths are configured via environment variables in `.env`:

- **Vault**: `$LIBRARIAN_VAULT_PATH` — The Obsidian vault root. All organized documents live here.
- **Data folder**: `$LIBRARIAN_DATA_FOLDER` — Working directory containing `input/`, `log/`, `staging/`, `backups/`, and runtime data.
- **Input paths**: `$LIBRARIAN_INPUT_PATHS` — Comma-separated list of additional input folders. `$LIBRARIAN_DATA_FOLDER/input` is always included.
- **Database**: `$LIBRARIAN_DB_PATH` — SQLite index. Defaults to `$LIBRARIAN_DATA_FOLDER/librarian.db`.
- **Log directory**: `$LIBRARIAN_DATA_FOLDER/log/` — Centralized log output for all events, reports, and processing activity.
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

- `Librarian.Repo` — Ecto SQLite3 database access
- `Librarian.Vault.Watcher` — Filesystem change detection with 2s debounce for Google Drive sync
- `Librarian.Vault.Backup` — File backup before overwrite (30-day retention, daily pruning)
- `Librarian.Processor` — Document format conversion (Pandoc/OCR)
- `Librarian.Staging` — Staging folder handoff between Elixir (conversion) and agent (classification)
- `Librarian.Indexer` — SQLite FTS5 indexing, search, and relationship tracking
- `Librarian.Input` — Multi-folder input monitor (15-minute interval, triggers conversion and staging)
- `Librarian.Reporter` — Daily report generation + backup pruning

## Container Lifecycle

The `librarian` Docker service is configured with `restart: always` to ensure it stays running.
If you detect the container is down, run `docker compose up -d` to restore it.
