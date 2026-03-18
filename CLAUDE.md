# Openclaw Librarian Agent — Developer Guide

> This file is for **development agents** (Claude Code, CI bots) working on this repository.
> For the Librarian agent's own instructions, see `AGENTS.md`.

## Quick Orientation

This repo defines **the Librarian**, an openclaw agent that organizes, summarizes, and retrieves documents in an Obsidian-compatible vault. The codebase has two audiences:

| Audience | Entry Point | Purpose |
|----------|-------------|---------|
| Dev agents (you) | `CLAUDE.md` (this file) | Improve, test, and maintain the Librarian |
| Openclaw Librarian | `AGENTS.md` → `IDENTITY.md`, `SOUL.md`, etc. | Runtime behavior of the agent |

## Project Structure

```
├── AGENTS.md                 # Openclaw agent config (Librarian reads this)
├── IDENTITY.md               # Librarian's identity
├── SOUL.md                   # Librarian's values and behavior
├── BOOT.md                   # Startup tasks
├── HEARTBEAT.md              # Periodic tasks
├── TOOLS.md                  # Environment-specific tool config
├── input/                    # Local project input folder (mounted into container)
├── spec/                     # Detailed specifications
│   ├── ARCHITECTURE.md       # System design, data flow, ADR index
│   ├── STRUCTURE.md          # Document organization rules
│   ├── PIPELINES.md          # Pipeline definitions and usage
│   ├── TESTING.md            # Testing strategy and instructions
│   ├── LIBRARIES.md.example  # Library definitions template
│   ├── TROUBLESHOOTING.md    # Known issues and fixes
│   └── LEARNINGS.md          # Accumulated agent learnings
├── .archgate/adrs/           # Architecture Decision Records
├── .github/workflows/        # GitHub Actions CI/CD
├── tools/pipeline_runner/    # Python pipelines (Poetry, pytest)
├── lib/librarian/            # Elixir application source
├── config/                   # Elixir configuration
├── scripts/                  # Containerized utility scripts
├── docker-compose.yml        # Zero-Install service definitions
├── Dockerfile                # Librarian service container
├── mix.exs                   # Elixir project definition
└── test/                     # Elixir tests
```

## Key Concepts

### Two-stage pipeline
Documents flow through: **Elixir (conversion)** → **staging folder** → **Agent (classification)**. The Elixir service converts formats via Pandoc and writes to `$LIBRARIAN_DATA_FOLDER/staging/`. The Librarian agent reads pending items, classifies, and files into the vault. See `Librarian.Staging` for the protocol.

### Multi-folder input
The `Librarian.Input` module monitors multiple input folders configured via `LIBRARIAN_INPUT_PATHS` (comma-separated). The `$LIBRARIAN_DATA_FOLDER/input` path is always included. The local `input/` directory is also mounted into the container.

### Debounce & conflict safety
The `Librarian.Vault.Watcher` uses a **2-second debounce window** to coalesce rapid filesystem events from Google Drive sync. Own-writes are tracked with timestamps so the watcher ignores changes it caused. Before overwriting human-edited files, `Librarian.Vault.Backup` creates timestamped copies in `$LIBRARIAN_DATA_FOLDER/backups/` (30-day retention, pruned daily).

## Key Rules

1. **No sensitive data in git.** Paths, emails, API keys, and library names go in `.env` (gitignored). Use `.env.example` as the template. CI enforces this via the `sensitive-data-check` workflow.
2. **`spec/LIBRARIES.md` is gitignored.** It contains real library names that may reveal business relationships. Only `spec/LIBRARIES.md.example` is committed.
3. **Zero-Install policy.** All tooling runs in containers. No local Elixir/Erlang install required. Use `docker compose` for everything.
4. **Elixir for long-running services.** Document processing pipelines, filesystem watchers, staging, and indexing run as Elixir GenServers inside Docker.
5. **Pandoc for format conversion.** The Docker image includes Pandoc. Shell out to it for docx/pptx/etc → markdown conversion.
6. **Containers must stay alive.** The `librarian` service uses `restart: always`. The agent checks container health in its heartbeat.

## Development Workflow

```bash
# Start all services (Elixir app, SQLite, watchers)
docker compose up -d

# Run full test suite (Elixir + Python)
docker compose run --rm pipeline-runner test

# Run Elixir tests only
docker compose exec librarian mix test

# Run Python pipeline tests only
cd tools/pipeline_runner && poetry run pytest

# Run ADR compliance checks
docker compose run --rm pipeline-runner archgate-check

# Open an IEx shell
docker compose exec librarian iex -S mix

# Process input folder manually
docker compose exec librarian mix librarian.process_input

# View logs
docker compose logs -f librarian
```

## CI/CD

GitHub Actions runs on every push/PR to `main`. See `.github/workflows/ci.yml`. Jobs:
- **Python Pipeline Tests** — ruff lint + pytest
- **Elixir Compile** — `mix compile --warnings-as-errors`
- **Elixir Tests** — `mix test`
- **ADR Compliance** — validates ADR frontmatter
- **Docker Build** — ensures both images build
- **Sensitive Data Audit** — scans for emails, API keys, absolute paths

## Deep Dive

For detailed specifications, read the `spec/` folder:

- **Architecture & data flow** → `spec/ARCHITECTURE.md` (references ADRs in `.archgate/adrs/`)
- **Pipelines** → `spec/PIPELINES.md`
- **Testing strategy** → `spec/TESTING.md`
- **Document organization rules** → `spec/STRUCTURE.md`
- **Library definitions** → `spec/LIBRARIES.md` (local only, see `.example`)
- **Troubleshooting** → `spec/TROUBLESHOOTING.md`
- **Learnings log** → `spec/LEARNINGS.md`
- **ADRs** → `.archgate/adrs/` (ARCH-001 through ARCH-006)

## Environment Variables

All configuration is in `.env`. See `.env.example` for the full list with descriptions.

| Variable | Purpose |
|----------|---------|
| `LIBRARIAN_VAULT_PATH` | Obsidian vault location |
| `LIBRARIAN_DATA_FOLDER` | Working data (input/, staging/, log/, backups/) |
| `LIBRARIAN_INPUT_PATHS` | Comma-separated additional input folders |
| `LIBRARIAN_DB_PATH` | SQLite index database |
| `LIBRARIAN_LOG_LEVEL` | Log verbosity |
| `OPENCLAW_PROVIDER_API_KEY` | AI provider API key |
