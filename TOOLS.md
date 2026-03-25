# Tools

Environment-specific configuration for this Librarian instance.
Skills define *how* tools work. This file captures *your* setup.

## Paths

All paths are configured via environment variables in `.env`:

- **Vault**: `$LIBRARIAN_VAULT_PATH` — The Obsidian vault root. All organized documents live here.
- **Primary data folder**: `$LIBRARIAN_PRIMARY_DATA_FOLDER` — Single host path for Docker volume mount. This is where staging, log, backups, and DB live.
- **Data folders**: `$LIBRARIAN_DATA_FOLDER` — Comma-separated list of data folder paths. First is primary. Each gets `input/` and `processed/` directories.
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
- `Librarian.Input` — Multi-folder input monitor (15-minute interval, triggers conversion and staging, moves processed files)
- `Librarian.Reporter` — Daily report generation + backup pruning
- `Librarian.Archiver` — Weekly compression of processed documents (Sundays at midnight UTC)

## Atlassian Integration (ARCH-007)

On-demand access to Jira, Confluence, and Jira Product Discovery (JPD):

- `Librarian.Atlassian.Client` — HTTP client with Basic auth, automatic pagination, rate limiting, and exponential backoff retry
- `Librarian.Atlassian.Cache` — Filesystem cache at `$LIBRARIAN_DATA_FOLDER/cache/atlassian/` (default 1h TTL)
- `Librarian.Atlassian.Jira` — Issue search (JQL), get issue details, comments, changelogs. Also handles JPD ideas (same API)
- `Librarian.Atlassian.Confluence` — Page fetch, CQL search, space listing. Converts XHTML → markdown via Pandoc

Accounts are configured via numbered env vars (`ATLASSIAN_1_URL`, `ATLASSIAN_1_EMAIL`, `ATLASSIAN_1_TOKEN`, etc.). See `.env.example`.

## Inter-Agent Message Queue (IAMQ)

The Librarian connects to the Openclaw IAMQ service as `librarian_agent`:

- `Librarian.IAMQ` — GenServer that registers on startup, heartbeats every 2 min, polls inbox every 30 sec
- **Dual-mode**: tries HTTP API (`$IAMQ_HTTP_URL`, default port 18790) first, falls back to file-based queue (`$IAMQ_QUEUE_PATH`)
- Incoming messages are logged to `$LIBRARIAN_DATA_FOLDER/log/iamq-*.json`
- Send messages via `Librarian.IAMQ.send_message/4` or `Librarian.IAMQ.broadcast/3`
- **Workspace inbox**: other agents may also write messages directly to `inbox/` in this workspace — check during heartbeat

## Notifications

Telegram notifications are handled by the Openclaw platform. The Librarian agent itself does not manage notification delivery — all generated content (processed documents, reports, archives, errors) is communicated through Openclaw's built-in notification channels.

## Container Lifecycle

The `librarian` Docker service is configured with `restart: always` to ensure it stays running.
If you detect the container is down, run `docker compose up -d` to restore it.
