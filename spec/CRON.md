# Cron Schedules — openclaw-librarian-agent

## Overview

The Librarian agent runs a daily vault reindex to keep its search index current.
It also handles document filing on-demand (triggered by IAMQ messages from peer
agents like Journalist). All crons are registered with IAMQ on startup.

## Schedules

### reindex_vault
- **Expression**: `0 4 * * *` (04:00 UTC daily)
- **Purpose**: Walk the entire Obsidian vault directory tree, rebuild the SQLite
  search index (Ecto-backed), resolve broken internal links, prune stale entries,
  and update the `last_indexed` metadata. Runs during low-activity hours to avoid
  conflicts with agent writes.
- **Trigger**: Delivered via IAMQ message `cron::reindex_vault`
- **Handler**: `Librarian.Indexer.reindex_all/0` (Elixir)
- **Expected duration**: 5–20 minutes depending on vault size (scales with number
  of notes; a 5000-note vault takes ~8 minutes)
- **On failure**: Log error to `$LIBRARIAN_DATA_FOLDER/logs/`; send IAMQ warning
  to `agent_claude`; previous index remains in use (stale but functional)

### daily_archive
- **Expression**: `30 3 * * *` (03:30 UTC daily, runs before reindex)
- **Purpose**: Move processed staging files older than 7 days from
  `$LIBRARIAN_DATA_FOLDER/staging/` to the archive folder. Prune Confluence
  backup copies older than 30 days. Never deletes vault content.
- **Trigger**: Delivered via IAMQ message `cron::daily_archive`
- **Handler**: `Librarian.Archive.run_daily_cleanup/0`
- **Expected duration**: Under 2 minutes
- **On failure**: Skip silently; staging files accumulate harmlessly

### confluence_sync
- **Expression**: `0 6 * * 1` (06:00 UTC Monday)
- **Purpose**: Sync the weekly handoff folder to Confluence: upload new documents,
  update changed pages, add index entries. Uses the Atlassian API.
- **Trigger**: Delivered via IAMQ message `cron::confluence_sync`
- **Handler**: `Librarian.Atlassian.sync_weekly/0`
- **Expected duration**: 2–5 minutes (rate-limited by Atlassian API)
- **On failure**: Log error; retry next Monday; operator can trigger manually

## Cron Registration

Registered with IAMQ on startup via `POST /crons`:

```json
[
  {"subject": "cron::daily_archive",   "expression": "30 3 * * *"},
  {"subject": "cron::reindex_vault",   "expression": "0 4 * * *"},
  {"subject": "cron::confluence_sync", "expression": "0 6 * * 1"}
]
```

## Manual Trigger

```bash
# Trigger a reindex via IAMQ
curl -X POST http://127.0.0.1:18790/send \
  -H "Content-Type: application/json" \
  -d '{"from":"developer","to":"librarian_agent","type":"request","priority":"HIGH","subject":"librarian.index","body":{}}'

# Or via Elixir Mix task (local dev)
cd /path/to/librarian && mix librarian.reindex
```

---

**Related:** `spec/API.md`, `spec/COMMUNICATION.md`, `spec/ARCHITECTURE.md`

## References

- [IAMQ Cron Subsystem](https://github.com/r3dlex/openclaw-inter-agent-message-queue/blob/main/spec/CRON.md) — how cron schedules are stored and fired
- [IAMQ API — Cron endpoints](https://github.com/r3dlex/openclaw-inter-agent-message-queue/blob/main/spec/API.md#cron-scheduling)
- [IamqSidecar.MqClient.register_cron/3](https://github.com/r3dlex/openclaw-inter-agent-message-queue/tree/main/sidecar) — Elixir sidecar helper
- [openclaw-main-agent](https://github.com/r3dlex/openclaw-main-agent) — orchestrates cron-triggered pipelines
