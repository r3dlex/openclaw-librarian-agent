# IAMQ Protocol

> Messaging protocol for the Openclaw Inter-Agent Message Queue.
> This document defines message formats, lifecycle flows, and error handling for agents communicating via IAMQ.

## Overview

IAMQ is a centralized HTTP-based message broker that connects Openclaw agents. Each agent:
1. **Registers** on startup with its identity and capabilities
2. **Heartbeats** periodically to signal liveness
3. **Polls** its inbox for incoming messages
4. **Sends** messages to specific agents or broadcasts to all

There are no persistent connections — all communication uses short-lived HTTP requests (polling model). This simplifies deployment and makes agents resilient to transient network failures.

## Agent Identity

Each agent registers with a fixed identity:

| Field | Type | Description |
|-------|------|-------------|
| `agent_id` | string | Unique identifier (e.g., `librarian_agent`) |
| `name` | string | Human-readable display name (e.g., `Librarian`) |
| `emoji` | string | Visual identifier for UI display |
| `description` | string | One-line description of the agent's purpose |
| `capabilities` | string[] | List of capability tags (e.g., `["search", "summarize"]`) |
| `workspace` | string | Path to the agent's workspace directory |

The Librarian registers as:

```json
{
  "agent_id": "librarian_agent",
  "name": "Librarian",
  "emoji": "📚",
  "description": "Document archivist and knowledge organizer — search, summarize, archive",
  "capabilities": ["search", "summarize", "archive", "knowledge_management"],
  "workspace": "<LIBRARIAN_WORKSPACE_PATH>"
}
```

## Agent Network

Known agents in the Openclaw network:

| Agent ID | Role |
|----------|------|
| `librarian_agent` | Document organization and retrieval |
| `mail_agent` | Email processing |
| `journalist_agent` | Research and writing |
| `archivist_agent` | Long-term archival |
| `gitrepo_agent` | Git repository management |
| `sysadmin_agent` | System administration |
| `health_fitness` | Health and fitness tracking |
| `workday_agent` | Work schedule management |
| `instagram_agent` | Social media |
| `agent_claude` | General-purpose assistant |
| `main` | Orchestrator / gateway |

## Message Format

### Outgoing Message Payload

```json
{
  "from": "librarian_agent",
  "to": "mail_agent",
  "type": "info",
  "priority": "NORMAL",
  "subject": "Document ready",
  "body": "Filed report to vault at Library/Reports/2026-03-22.md",
  "replyTo": null,
  "expiresAt": null
}
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `from` | string | yes | — | Sender agent ID (set automatically) |
| `to` | string | yes | — | Recipient agent ID, or `"broadcast"` for all |
| `type` | string | no | `"info"` | Message semantics (see § Message Types) |
| `priority` | string | no | `"NORMAL"` | `"LOW"`, `"NORMAL"`, or `"HIGH"` |
| `subject` | string | yes | — | Short summary of the message |
| `body` | string | yes | — | Full message content |
| `replyTo` | string | no | `null` | Message ID this is a reply to |
| `expiresAt` | string | no | `null` | ISO 8601 timestamp after which the message should be discarded |

### Message Types

| Type | Semantics | Response expected |
|------|-----------|-------------------|
| `info` | Informational notification — no action required | No |
| `request` | Asks the recipient to perform an action or answer a question | Yes — reply with `type: "response"` |
| `response` | Reply to a previous `request` — must include `replyTo` | No |
| `error` | Reports a problem — recipient may act if relevant | Optional |

### Priority Levels

| Priority | Usage |
|----------|-------|
| `LOW` | Background notifications, FYI messages |
| `NORMAL` | Standard inter-agent communication |
| `HIGH` | Time-sensitive requests requiring prompt attention |

## Lifecycle Flows

### Registration

```
Agent                           IAMQ Service
  │                                  │
  │  POST /register                  │
  │  { agent_id, name, emoji, ... }  │
  │ ──────────────────────────────►  │
  │                                  │
  │  200 OK                          │
  │ ◄──────────────────────────────  │
  │                                  │
  │  (start heartbeat + polling)     │
  │                                  │
```

- On success: schedule heartbeat (every 2 min) and inbox polling (every 30 sec)
- On failure: retry registration every 30 seconds until successful

### Heartbeat

```
Agent                           IAMQ Service
  │                                  │
  │  POST /heartbeat                 │
  │  { agent_id: "librarian_agent" } │
  │ ──────────────────────────────►  │
  │                                  │
  │  200 OK                          │
  │ ◄──────────────────────────────  │
  │                                  │
  │  (repeat every 2 minutes)        │
  │                                  │
```

Heartbeat failures are logged but do not stop the cycle. The next heartbeat fires on schedule regardless.

### Inbox Polling

```
Agent                           IAMQ Service
  │                                  │
  │  GET /inbox/{agent_id}           │
  │      ?status=unread              │
  │ ──────────────────────────────►  │
  │                                  │
  │  200 { messages: [...] }         │
  │ ◄──────────────────────────────  │
  │                                  │
  │  (for each message:)             │
  │    1. Log to filesystem          │
  │    2. PATCH /messages/{id}       │
  │       { status: "read" }         │
  │ ──────────────────────────────►  │
  │                                  │
  │  (repeat every 30 seconds)       │
  │                                  │
```

### Message Send

```
Agent                           IAMQ Service
  │                                  │
  │  POST /send                      │
  │  { from, to, type, subject, .. } │
  │ ──────────────────────────────►  │
  │                                  │
  │  200 OK                          │
  │ ◄──────────────────────────────  │
  │                                  │
```

### Broadcast

Broadcast uses the same send flow with `to: "broadcast"`. The IAMQ service distributes the message to all registered agents.

## Message Logging

Incoming messages are written to the filesystem for the Librarian agent to process during its hourly heartbeat cycle:

- **Directory**: `$LIBRARIAN_DATA_FOLDER/log/`
- **Filename**: `iamq-{timestamp}-{from}.json`
- **Timestamp format**: ISO 8601 with colons replaced by hyphens (filesystem-safe)
- **Content**: Full message JSON, pretty-printed

Example: `iamq-2026-03-22T14-30-00Z-mail_agent.json`

The Librarian agent checks these logs hourly and acts on them:
- `request` messages → process and reply
- `info` messages → log and file if relevant
- `error` messages → investigate and respond if applicable

## Timing

| Event | Interval | Notes |
|-------|----------|-------|
| Registration | On startup | Retries every 30s on failure |
| Heartbeat | Every 2 minutes | Continues on failure |
| Inbox poll | Every 30 seconds | Automatic via GenServer |
| Message processing | Every hour | Agent reads logged messages and acts |

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Registration fails | Log warning, retry in 30 seconds |
| Heartbeat fails | Log warning, continue heartbeat cycle |
| Inbox poll fails | Log warning, continue poll cycle |
| Send fails | Return error tuple to caller |
| HTTP timeout | 5-second receive timeout on all requests |
| Inbox poll exception | Rescue, log error, continue poll cycle |

All HTTP errors return `{:error, {:http, status, body}}`. Network/connection errors return `{:error, exception}`.

The GenServer is supervised with `:one_for_one` strategy — if the IAMQ process crashes, the supervisor restarts it, triggering re-registration.

## Related

- `spec/API.md` — IAMQ HTTP endpoint reference
- `spec/ARCHITECTURE.md` — System architecture and component overview
- `AGENTS.md` § Inter-Agent Communication — Agent-facing usage guide
- `TOOLS.md` § Inter-Agent Message Queue — Service configuration
- `BOOT.md` — Startup IAMQ verification steps
- `HEARTBEAT.md` — Periodic IAMQ inbox processing
