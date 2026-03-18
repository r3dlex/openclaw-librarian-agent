---
id: ARCH-001
title: Two-Stage Document Processing Pipeline
domain: architecture
rules: false
---

# ARCH-001: Two-Stage Document Processing Pipeline

## Context

The Librarian agent needs to process documents from various formats into organized markdown in a vault. Using the AI agent for every step (conversion, classification, filing) would be token-inefficient. Format conversion is deterministic and repeatable, while classification requires judgment.

**Alternatives considered:**
1. Agent handles everything end-to-end → expensive, slow, wasteful
2. Elixir handles everything including classification → can't make nuanced decisions
3. **Two-stage split** → Elixir converts, agent classifies

## Decision

Split document processing into two stages with a filesystem-based handoff:

| Stage | Owner | Responsibility |
|-------|-------|---------------|
| Stage 1: Conversion | Elixir (`Librarian.Input` + `Librarian.Processor`) | Format conversion via Pandoc/OCR, staging |
| Handoff | `Librarian.Staging` | `<id>.md` + `<id>.meta.json` in `$LIBRARIAN_DATA_FOLDER/staging/` |
| Stage 2: Classification | Librarian Agent (AI) | Library assignment, tagging, relationship mapping, vault filing |

### Do's and Don'ts

- **Do** use the staging folder as the sole handoff mechanism
- **Do** include processing instructions in `.meta.json`
- **Do** clean up staged items after 24 hours
- **Don't** have the agent call Pandoc directly
- **Don't** skip the staging folder for "simple" documents

## Consequences

**Positive:** Token-efficient, clear separation of concerns, resumable after crashes.
**Negative:** Adds latency (two steps instead of one), staging folder is another state to manage.
**Risks:** Staging folder could accumulate if agent is offline for extended periods.
