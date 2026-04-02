# Communication

> How the Librarian Agent communicates with peer agents via IAMQ.

## IAMQ Registration

The agent registers on startup at `$IAMQ_HTTP_URL` (HTTP) with file-based fallback via `$IAMQ_QUEUE_PATH`.

```json
{
  "agent_id": "librarian_agent",
  "capabilities": [
    "search",
    "summarize",
    "archive",
    "knowledge_management"
  ]
}
```

## Dual-Mode Connectivity

The Librarian supports two IAMQ transport modes:

1. **HTTP** — Primary. Registration, heartbeats, and inbox polling via the IAMQ HTTP API at `$IAMQ_HTTP_URL`.
2. **File-based fallback** — When the IAMQ service is unreachable, the agent reads/writes JSON files in `$IAMQ_QUEUE_PATH/librarian_agent/` on disk.

The agent checks HTTP connectivity on startup. If unavailable, it falls back to the file-based queue automatically.

## Incoming Message Routing

Messages are routed by subject pattern:

| Subject Contains | Action |
|-----------------|--------|
| `search`, `find` | Query the vault index, return matching document metadata |
| `archive`, `store` | Accept content and file it into the Obsidian vault |
| `summarize`, `summary` | Summarize the referenced document and return the result |

### Briefing Archival (from journalist_agent)

The Journalist Agent sends full briefing content for permanent storage. The Librarian files it into the vault under the appropriate library and date structure.

```json
{
  "from": "journalist_agent",
  "to": "librarian_agent",
  "type": "info",
  "subject": "News Briefing — 2026-03-23",
  "body": {
    "action": "archive",
    "content_type": "text/markdown",
    "content": "# Morning Briefing — 2026-03-23\n..."
  }
}
```

## Outgoing Messages

### Search Results

```json
{
  "from": "librarian_agent",
  "to": "main",
  "type": "response",
  "priority": "NORMAL",
  "subject": "Search results: quarterly report",
  "body": "Found 3 documents:\n1. 2026-Q1-report.md (modified: 2026-03-15)\n2. 2025-Q4-report.md (modified: 2025-12-20)\n3. 2025-Q3-report.md (modified: 2025-09-18)\n\nUse 'summarize <filename>' for details."
}
```

### Status Reports

```json
{
  "from": "librarian_agent",
  "to": "main",
  "type": "info",
  "priority": "NORMAL",
  "subject": "Librarian status",
  "body": "Vault: 1,247 documents | Index: healthy | Last ingest: 2m ago"
}
```

## Message Logging

All IAMQ messages (incoming and outgoing) are logged to:

```
$LIBRARIAN_DATA_FOLDER/log/iamq-YYYY-MM-DD.json
```

One JSON object per line. Logs are rotated daily.

## Peer Agents

| Agent | Relationship |
|-------|-------------|
| `journalist_agent` | Sends briefings and research content for archival |
| `main` | Receives status reports, responds to search/summarize requests |
| `broadcast` | Receives swarm-wide announcements |

## Message Rules

- Return **metadata only** in search results (filename, date, summary), not full document content. Full content is too large for IAMQ messages.
- Summarize, don't copy. When summarizing for a peer agent, produce a concise summary rather than forwarding the entire document.
- Keep response bodies under 500 characters for broadcast; full responses to specific agents can be longer.

## Related

- Architecture: [ARCHITECTURE.md](ARCHITECTURE.md)
- Safety rules: [SAFETY.md](SAFETY.md)
- Vault structure: [STRUCTURE.md](STRUCTURE.md)

---
*Owner: librarian_agent*

## References

- [IAMQ HTTP API](https://github.com/r3dlex/openclaw-inter-agent-message-queue/blob/main/spec/API.md)
- [IAMQ WebSocket Protocol](https://github.com/r3dlex/openclaw-inter-agent-message-queue/blob/main/spec/PROTOCOL.md)
- [IAMQ Cron Scheduling](https://github.com/r3dlex/openclaw-inter-agent-message-queue/blob/main/spec/CRON.md)
- [Sidecar Client](https://github.com/r3dlex/openclaw-inter-agent-message-queue/tree/main/sidecar)
- [openclaw-main-agent](https://github.com/r3dlex/openclaw-main-agent)
