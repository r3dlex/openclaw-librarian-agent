---
id: ARCH-007
title: Atlassian On-Demand Integration
domain: architecture
rules: true
files: ["lib/librarian/atlassian/**/*.ex", "config/runtime.exs"]
---

# ARCH-007: Atlassian On-Demand Integration

## Context

The Librarian needs access to knowledge stored outside the vault — Jira issues, Confluence pages, and Jira Product Discovery (JPD) insights. This content may be referenced by documents in the vault, requested as part of a task, or needed to enrich existing library entries.

Multiple Atlassian accounts may be involved (e.g., different organizations or workspaces), so the integration must support multi-account configuration.

## Decision

### Pull model, not sync

The Atlassian integration uses an **on-demand pull model**. The Librarian agent calls Elixir modules when it needs Atlassian content — there is no periodic sync. This avoids:
- Unnecessary API calls and rate limit pressure
- Stale data accumulation
- Complex conflict resolution between vault and Atlassian

### Multi-account support

Accounts are configured via numbered environment variables:

```
ATLASSIAN_1_LABEL=work
ATLASSIAN_1_URL=https://myorg.atlassian.net
ATLASSIAN_1_EMAIL=user@example.com
ATLASSIAN_1_TOKEN=atl_xxx
```

The Elixir runtime parses `ATLASSIAN_N_*` variables at startup and builds an account registry. Modules accept an account label (or default to the first configured account).

### JPD via standard Jira API

Jira Product Discovery uses the standard Jira REST API — the same `Librarian.Atlassian.Jira` module handles both regular Jira issues and JPD ideas. No separate client is needed.

### Filesystem cache

Fetched content is cached at `$LIBRARIAN_DATA_FOLDER/cache/atlassian/` with configurable TTL (default 1 hour). This reduces API calls when the agent references the same content multiple times during a session.

### Confluence → Markdown via Pandoc

Confluence pages are returned as XHTML. The integration converts them to markdown using Pandoc (`pandoc -f html -t markdown --wrap=none`), consistent with the existing `Librarian.Processor` pattern.

## Consequences

- **Positive**: Agent can enrich vault documents with Jira/Confluence/JPD context without manual export.
- **Positive**: Multi-account support allows working across organizational boundaries.
- **Positive**: On-demand model keeps API usage proportional to actual need.
- **Negative**: First access to uncached content has latency (API call + conversion).
- **Negative**: Cache invalidation is time-based only; stale reads are possible within TTL window.

## Related

- ARCH-001 — Two-stage pipeline (similar pull-then-process pattern)
- ARCH-003 — Zero-install containers (Pandoc available in container for Confluence conversion)
