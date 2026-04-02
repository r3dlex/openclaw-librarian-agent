# API — openclaw-librarian-agent

## Overview

The Librarian agent accepts documents from peer agents via IAMQ and files them
into the Obsidian vault. It also accepts input via a monitored folder
(`$LIBRARIAN_DATA_FOLDER/input/`). There is no HTTP API exposed to other agents.

---

## IAMQ Message Interface

### Incoming messages accepted by `librarian_agent`

| Subject | Purpose | Body fields |
|---------|---------|-------------|
| `librarian.file` | File a document into the vault | `source_path: string`, `category?: string`, `date?: string` |
| `librarian.index` | Trigger a full vault reindex | — |
| `librarian.search` | Search the vault index | `query: string`, `limit?: number` |
| `librarian.status` | Return vault stats and last index timestamp | — |
| `librarian.archive` | Move old staging files to archive | — |
| `status` | Return agent health | — |

#### Example: file a document from the Journalist

```json
{
  "from": "journalist_agent",
  "to": "librarian_agent",
  "type": "request",
  "priority": "NORMAL",
  "subject": "librarian.file",
  "body": {
    "source_path": "/data/journalist/log/2026-04-02-morning.md",
    "category": "news_briefings",
    "date": "2026-04-02"
  }
}
```

#### Example response

```json
{
  "from": "librarian_agent",
  "to": "journalist_agent",
  "type": "response",
  "priority": "NORMAL",
  "subject": "librarian.file.result",
  "body": {
    "status": "filed",
    "destination": "News Briefings/2026/04/2026-04-02-morning.md",
    "vault": "main"
  }
}
```

#### Example: search the vault

```json
{
  "from": "agent_claude",
  "to": "librarian_agent",
  "type": "request",
  "subject": "librarian.search",
  "body": {"query": "weekly health report April 2026", "limit": 5}
}
```

---

## Folder Input Interface

Documents dropped into `$LIBRARIAN_DATA_FOLDER/input/` (or any path listed in
`LIBRARIAN_INPUT_PATHS`) are picked up automatically within 2 seconds. The
`Librarian.Input` module watches these folders using filesystem events.
The agent classifies the document and files it into the appropriate vault location.

Supported formats: `.md`, `.pdf`, `.docx`, `.txt`, `.html`

The Elixir `Librarian.Staging` module converts non-markdown formats via Pandoc
before handing off to the agent for classification.

---

## Atlassian Integration (Outbound)

The Librarian can push documents to Confluence via the Atlassian API. This is
triggered by the agent placing a document in a designated vault folder or by
an explicit `librarian.file` message with `destination: "confluence"`.
Credentials are configured via `ATLASSIAN_API_TOKEN` and `ATLASSIAN_BASE_URL`.

---

**Related:** `spec/COMMUNICATION.md`, `spec/ARCHITECTURE.md`, `spec/STRUCTURE.md`
