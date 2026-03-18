---
id: ARCH-006
title: Pipeline-Driven Testing and Validation
domain: architecture
rules: true
files: ["tools/pipeline_runner/**/*.py", "test/**/*.exs"]
---

# ARCH-006: Pipeline-Driven Testing and Validation

## Context

The system spans two runtimes (Elixir + Python), multiple services, and architectural decisions enforced via ADRs. Testing must cover all layers and be runnable without local tooling installation.

## Decision

All testing and validation is orchestrated through the Python `pipeline_runner` tool, which executes steps inside Docker containers. Testing is organized into layers:

| Layer | Tool | What it tests |
|-------|------|--------------|
| Unit (Elixir) | `mix test` | Individual modules — Processor, Indexer, Staging, Backup |
| Unit (Python) | `pytest` | Pipeline runner framework and CLI wiring |
| Integration | `pipeline document-processing --dry-run` | End-to-end document flow |
| ADR compliance | `pipeline archgate-check` | Codebase against architectural decisions |
| Index integrity | `pipeline index-validation` | SQLite FTS5 consistency |

### Test requirements

- Every pipeline must be testable via `--dry-run` or `--validate-only` flag
- ADR frontmatter is validated by `test_pipelines.py::TestADRFrontmatter`
- New Elixir modules must have corresponding tests in `test/`
- New pipelines must have CLI help tests in `test_pipelines.py`

### Do's and Don'ts

- **Do** run `pipeline test` before committing
- **Do** add `--dry-run` flags to destructive pipeline commands
- **Do** test ADR frontmatter validity in Python tests
- **Don't** skip tests by commenting them out
- **Don't** require local Elixir or Python to run tests — use Docker

## Compliance and Enforcement

### Automated rules
- All pipeline commands must have `--help` output
- All ADRs must have valid YAML frontmatter
- Test files must exist for both Elixir (`test/`) and Python (`tools/pipeline_runner/tests/`)

## References

- `spec/TESTING.md` — Full testing strategy and instructions
- `spec/PIPELINES.md` — Pipeline definitions and usage
