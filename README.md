<p align="center">
  <img src="assets/banner.svg" alt="openclaw-librarian-agent" width="600">
</p>

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

## Inter-Agent Message Queue (IAMQ)

The Librarian participates in the Openclaw inter-agent network via the **Inter-Agent Message Queue** (IAMQ). It registers as `librarian_agent` and advertises four capabilities: **search**, **summarize**, **archive**, and **knowledge_management**.

### Dual-mode connectivity

| Mode | Module | Transport | Default URL |
|------|--------|-----------|-------------|
| HTTP | `Librarian.IAMQ` | REST polling + file-based fallback | `http://127.0.0.1:18790` |
| WebSocket | `Librarian.MqWsClient` | Real-time push via WebSockex | `ws://127.0.0.1:18793/ws` |

Both modes run concurrently. The HTTP client (`Librarian.IAMQ`) polls the inbox on a configurable interval and falls back to a **file-based queue** (JSON files per the IAMQ `PROTOCOL.md` spec) when the HTTP service is unreachable. The WebSocket client (`Librarian.MqWsClient`) receives messages instantly, registers on connect, and maintains a periodic heartbeat.

### Cross-agent workflows

- **Receives briefings from `journalist_agent`** — The Journalist sends finished briefings to the Librarian for archival into the Obsidian vault.
- **Staging health reports** — The `Librarian.StagingWorker` runs hourly to detect orphaned items (status `"filed"` but no `vault_path`), clean up stale pending items, and report staging health via IAMQ.

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IAMQ_HTTP_URL` | `http://127.0.0.1:18790` | IAMQ HTTP API base URL |
| `IAMQ_WS_URL` | `ws://127.0.0.1:18793/ws` | IAMQ WebSocket URL |
| `IAMQ_AGENT_ID` | `librarian_agent` | Agent identity in the IAMQ registry |
| `IAMQ_QUEUE_PATH` | *(none)* | Path to file-based fallback queue directory |
| `IAMQ_HEARTBEAT_MS` | `300000` (5 min) | HTTP heartbeat interval |
| `IAMQ_POLL_MS` | `60000` (1 min) | HTTP inbox poll interval |

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

## Related

- [openclaw-inter-agent-message-queue](https://github.com/r3dlex/openclaw-inter-agent-message-queue) — IAMQ: message bus, agent registry, and cron scheduler
  - [HTTP API reference](https://github.com/r3dlex/openclaw-inter-agent-message-queue/blob/main/spec/API.md)
  - [Cron subsystem](https://github.com/r3dlex/openclaw-inter-agent-message-queue/blob/main/spec/CRON.md)
  - [Sidecar client](https://github.com/r3dlex/openclaw-inter-agent-message-queue/tree/main/sidecar)
- [openclaw-main-agent](https://github.com/r3dlex/openclaw-main-agent) — Cross-agent pipeline orchestrator

## License

[MIT](LICENSE)
