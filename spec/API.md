# IAMQ API Reference

> HTTP endpoint reference for the Openclaw Inter-Agent Message Queue service.
> Base URL: `$IAMQ_URL` (default: `http://127.0.0.1:18790`)

## Endpoints

### `POST /register`

Register an agent with the IAMQ service. Call on startup; safe to call multiple times (idempotent).

**Request:**

```json
{
  "agent_id": "librarian_agent",
  "name": "Librarian",
  "emoji": "📚",
  "description": "Document archivist and knowledge organizer — search, summarize, archive",
  "capabilities": ["search", "summarize", "archive", "knowledge_management"],
  "workspace": "/path/to/workspace"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_id` | string | yes | Unique agent identifier |
| `name` | string | yes | Human-readable display name |
| `emoji` | string | yes | Visual identifier |
| `description` | string | yes | One-line agent description |
| `capabilities` | string[] | yes | Capability tags for discovery |
| `workspace` | string | yes | Agent's workspace path |

**Response:** `200 OK`

---

### `POST /heartbeat`

Signal that the agent is still alive. Call periodically (every 2 minutes) after registration.

**Request:**

```json
{
  "agent_id": "librarian_agent"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_id` | string | yes | The registered agent ID |

**Response:** `200 OK`

---

### `POST /send`

Send a message to a specific agent or broadcast to all.

**Request:**

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
| `from` | string | yes | — | Sender agent ID |
| `to` | string | yes | — | Recipient agent ID, or `"broadcast"` |
| `type` | string | no | `"info"` | One of: `"info"`, `"request"`, `"response"`, `"error"` |
| `priority` | string | no | `"NORMAL"` | One of: `"LOW"`, `"NORMAL"`, `"HIGH"` |
| `subject` | string | yes | — | Message subject line |
| `body` | string | yes | — | Full message body |
| `replyTo` | string | no | `null` | Message ID this replies to (use with `type: "response"`) |
| `expiresAt` | string | no | `null` | ISO 8601 expiry timestamp |

**Response:** `200 OK`

---

### `GET /agents`

List all currently registered and online agents.

**Request:** No body required.

**Response:**

```json
{
  "agents": [
    {
      "agent_id": "librarian_agent",
      "name": "Librarian",
      "emoji": "📚",
      "description": "Document archivist and knowledge organizer — search, summarize, archive",
      "capabilities": ["search", "summarize", "archive", "knowledge_management"],
      "workspace": "/path/to/workspace"
    },
    {
      "agent_id": "mail_agent",
      "name": "Mail Agent",
      "emoji": "📧",
      "description": "...",
      "capabilities": ["..."],
      "workspace": "..."
    }
  ]
}
```

---

### `GET /inbox/{agent_id}`

Fetch messages for a specific agent. Use the `status` query parameter to filter.

**Request:** `GET /inbox/librarian_agent?status=unread`

| Parameter | Type | Location | Description |
|-----------|------|----------|-------------|
| `agent_id` | string | path | The agent whose inbox to read |
| `status` | string | query | Filter by status: `"unread"`, `"read"`, or omit for all |

**Response:**

```json
{
  "messages": [
    {
      "id": "msg-uuid-1234",
      "from": "mail_agent",
      "to": "librarian_agent",
      "type": "request",
      "priority": "NORMAL",
      "subject": "File this attachment",
      "body": "Please file the attached document into the vault...",
      "replyTo": null,
      "expiresAt": null,
      "status": "unread",
      "createdAt": "2026-03-22T14:30:00Z"
    }
  ]
}
```

---

### `PATCH /messages/{id}`

Update a message's status (e.g., mark as read after processing).

**Request:**

```json
{
  "status": "read"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | string | yes | New message status (e.g., `"read"`) |

**Response:** `200 OK`

---

## Elixir Client Usage

The `Librarian.IAMQ` module wraps all endpoints. Use these functions instead of making raw HTTP calls:

```elixir
# Send a targeted message
Librarian.IAMQ.send_message("mail_agent", "Subject", "Body")
Librarian.IAMQ.send_message("journalist_agent", "Results", body,
  type: "response",
  reply_to: original_msg_id,
  priority: "HIGH"
)

# Broadcast to all agents
Librarian.IAMQ.broadcast("Vault reorganized", "Libraries restructured")

# List online agents
{:ok, agents} = Librarian.IAMQ.list_agents()
```

### Return Values

All client functions return:

| Result | Shape |
|--------|-------|
| Success | `{:ok, body}` — decoded JSON response body |
| HTTP error | `{:error, {:http, status_code, body}}` |
| Network error | `{:error, exception}` |

## curl Examples

Useful for debugging and boot verification (see `BOOT.md`):

```bash
# Check if the Librarian is registered
curl -s http://127.0.0.1:18790/agents | jq '.agents[] | select(.agent_id == "librarian_agent")'

# Check unread messages
curl -s http://127.0.0.1:18790/inbox/librarian_agent?status=unread | jq .

# Send a test message
curl -s -X POST http://127.0.0.1:18790/send \
  -H "Content-Type: application/json" \
  -d '{
    "from": "test",
    "to": "librarian_agent",
    "type": "info",
    "subject": "Test message",
    "body": "Hello from curl"
  }'

# Mark a message as read
curl -s -X PATCH http://127.0.0.1:18790/messages/MSG_ID \
  -H "Content-Type: application/json" \
  -d '{"status": "read"}'
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `IAMQ_URL` | `http://127.0.0.1:18790` | Base URL of the IAMQ service |
| `LIBRARIAN_WORKSPACE_PATH` | `""` | Workspace path sent during registration |

Set these in `.env`. See `.env.example` for the full template.

## HTTP Behavior

- **Timeout**: 5-second receive timeout on all requests
- **Success range**: HTTP 200–299
- **Content type**: `application/json` for all requests and responses
- **No authentication**: IAMQ is an internal service on the local network

## Related

- `spec/PROTOCOL.md` — Message format, lifecycle flows, and error handling
- `spec/ARCHITECTURE.md` — System architecture and component overview
- `AGENTS.md` § Inter-Agent Communication — Agent-facing usage guide
- `TOOLS.md` § Inter-Agent Message Queue — Service configuration
- `lib/librarian/iamq.ex` — Elixir client implementation
- `test/librarian/iamq_test.exs` — Test suite and usage examples
