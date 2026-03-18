# Openclaw Librarian Agent

An autonomous document organization agent built on [Openclaw](https://docs.openclaw.ai/). The Librarian ingests, converts, indexes, and organizes documents into a structured [Obsidian](https://obsidian.md/) vault.

## What It Does

- **Ingests documents** in many formats (docx, pptx, pdf, images, markdown, txt) and converts them to structured markdown
- **Organizes** documents into configurable libraries with consistent naming, tagging, and front matter
- **Indexes** everything with SQLite FTS5 for fast full-text search across date, topic, and content
- **Tracks relationships** between documents (references, supersedes, related)
- **Maintains glossaries** per library that grow over time
- **Watches the vault** for human edits and reindexes automatically
- **Generates daily reports** of processed documents and their destinations
- **Stays human-readable** — the vault is always browsable in Obsidian

## Architecture

```
Openclaw Gateway → Librarian Agent (AI decisions)
                         ↕
                   Elixir Service (Docker)
                   ├── Input (monitors input folder)
                   ├── Processor (Pandoc/OCR conversion)
                   ├── Staging (handoff to agent)
                   ├── Vault.Watcher (filesystem events, 2s debounce)
                   ├── Vault.Backup (pre-overwrite backups, 30-day retention)
                   ├── Indexer (SQLite FTS5)
                   └── Reporter (daily reports)
                         ↕
                   Obsidian Vault + SQLite DB
```

See [spec/ARCHITECTURE.md](spec/ARCHITECTURE.md) for the full system design.

## Quick Start

### Prerequisites

- Docker and Docker Compose
- An Obsidian vault (or any folder — the Librarian creates the structure)
- An Openclaw instance ([installation guide](https://docs.openclaw.ai/))

### Setup

```bash
# 1. Clone and configure
git clone https://github.com/r3dlex/openclaw-librarian-agent.git
cd openclaw-librarian-agent
cp .env.example .env
cp spec/LIBRARIES.md.example spec/LIBRARIES.md

# 2. Edit configuration
#    Set LIBRARIAN_VAULT_PATH and LIBRARIAN_DATA_FOLDER in .env
#    Define your libraries in spec/LIBRARIES.md

# 3. Run setup (creates directories, builds Docker image)
./scripts/setup.sh

# 4. Start the service
docker compose up -d

# 5. Verify
docker compose exec librarian /app/scripts/healthcheck.sh
```

### Usage

**Drop documents into the input folder** at `$LIBRARIAN_DATA_FOLDER/input/`. The Elixir service converts them and stages for the agent to classify (every 15 minutes), or trigger manually:

```bash
./scripts/process-input.sh
```

**Add processing instructions** by placing a companion `.md` file alongside the document:

```
input/
├── quarterly-review.pptx
└── quarterly-review.md    ← "Convert to meeting minutes, tag as Q1-2026"
```

**Generate a daily report**:

```bash
./scripts/daily-report.sh
```

## Configuration

All configuration is through environment variables in `.env`. See [.env.example](.env.example) for the full list.

| Variable | Description |
|----------|-------------|
| `LIBRARIAN_VAULT_PATH` | Path to the Obsidian vault |
| `LIBRARIAN_DATA_FOLDER` | Working directory (input/, staging/, logs/, backups/) |
| `LIBRARIAN_DB_PATH` | SQLite database path (optional) |
| `LIBRARIAN_LOG_LEVEL` | Log level: debug, info, warning, error |

## Pipelines

Operational pipelines are defined in `tools/pipeline_runner/` (Python, Poetry). All run inside Docker.

```bash
# Run full test suite
docker compose run --rm pipeline-runner test

# Run ADR compliance checks
docker compose run --rm pipeline-runner archgate-check

# Validate document processing flow
docker compose run --rm pipeline-runner document-processing --dry-run
```

See [spec/PIPELINES.md](spec/PIPELINES.md) for details. See [spec/TESTING.md](spec/TESTING.md) for the testing strategy.

## Project Structure

```
├── AGENTS.md              # Openclaw agent configuration
├── IDENTITY.md / SOUL.md  # Agent personality and values
├── BOOT.md / HEARTBEAT.md # Startup and periodic tasks
├── TOOLS.md               # Environment-specific tool config
├── spec/                  # Detailed specifications
│   ├── ARCHITECTURE.md    # System design + ADR index
│   ├── STRUCTURE.md       # Document organization rules
│   ├── PIPELINES.md       # Pipeline definitions
│   ├── TESTING.md         # Testing strategy
│   └── LIBRARIES.md       # Library definitions (local only)
├── .archgate/adrs/        # Architecture Decision Records
├── tools/pipeline_runner/  # Python CI/CD pipelines
├── lib/librarian/         # Elixir application
├── scripts/               # Containerized utility scripts
├── docker-compose.yml     # Service definitions
└── Dockerfile             # Zero-Install container
```

## Zero-Install Policy

No local Elixir, Erlang, Python, or Pandoc installation required. Everything runs inside Docker containers. The only prerequisites are Docker and Docker Compose.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Read [CLAUDE.md](CLAUDE.md) for development conventions
4. Run `docker compose run --rm pipeline-runner test` before submitting
5. Submit a pull request

## License

[MIT](LICENSE)
