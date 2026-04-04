<p align="center">
  <img src="assets/banner.svg" alt="openclaw-librarian-agent" width="600">
</p>

# Librarian

An autonomous document organization agent for the Openclaw ecosystem. The Librarian ingests, converts, indexes, and organizes documents into a structured [Obsidian](https://obsidian.md/) vault using Elixir/OTP for long-running services and Pandoc for format conversion.

## Features

- **Ingests documents** in many formats (docx, pptx, pdf, images, markdown, txt) and converts to markdown
- **Organizes** documents into configurable libraries with consistent naming, tagging, and front matter
- **Indexes** everything with SQLite FTS5 for fast full-text search across date, topic, and content
- **Tracks relationships** between documents (references, supersedes, related)
- **Maintains glossaries** per library that grow over time
- **Watches the vault** for human edits and reindexes automatically (2s debounce)
- **Generates daily reports** of processed documents and their destinations
- **Receives briefings** from journalist_agent for automatic archival

## Skills

| Skill | Description |
|-------|-------------|
| `document_archive` | Archive a document to the Obsidian vault with title, content, and tags |

Workspace skills also available: `iamq_message_send`, `log_learning`, `improve_skill`

Skills auto-improve via post-execution hooks and nightly batch review.

## Architecture

- **Language**: Elixir/OTP
- **IAMQ ID**: `librarian_agent`
- **Runtime**: Docker (zero-install, Pandoc included)

```
Input folder → Elixir (Pandoc conversion) → Staging → Agent (classification) → Obsidian Vault
                                                                                      ↕
                                                                               SQLite FTS5 Index
```

IAMQ dual-mode: HTTP polling (`Librarian.IAMQ`) + WebSocket push (`Librarian.MqWsClient`).

## Setup

```bash
git clone https://github.com/r3dlex/openclaw-librarian-agent.git
cd openclaw-librarian-agent
cp .env.example .env
cp spec/LIBRARIES.md.example spec/LIBRARIES.md
# Set LIBRARIAN_VAULT_PATH and LIBRARIAN_DATA_FOLDER in .env
./scripts/setup.sh
docker compose up -d
```

### Docker Volume Mounts

```yaml
- ../skills-cli:/skills-cli:ro
- ../skills:/workspace/skills:rw
- ./skills:/agent/skills:rw
```

Environment: `EMBEDDINGS_URL=http://host.docker.internal:18795`

## Development

```bash
# Full test suite
docker compose run --rm pipeline-runner test

# Elixir tests only
docker compose exec librarian mix test

# Process input folder manually
docker compose exec librarian mix librarian.process_input

# Daily report
./scripts/daily-report.sh
```

Drop documents into `$LIBRARIAN_DATA_FOLDER/input/`. The Elixir service converts and stages them; the agent classifies every 15 minutes.

## Related

- [openclaw-inter-agent-message-queue](https://github.com/r3dlex/openclaw-inter-agent-message-queue) — IAMQ message bus and agent registry
- [openclaw-main-agent](https://github.com/r3dlex/openclaw-main-agent) — Cross-agent pipeline orchestrator

## License

[MIT](LICENSE)
