# Pipelines

> Operational and CI/CD pipelines for the Openclaw Librarian Agent.
> All pipelines run inside Docker containers (zero-install).

## Overview

Pipelines are defined in `tools/pipeline_runner/` as a Python package using Poetry and Click.
Each pipeline orchestrates steps that execute inside Docker containers.

```
tools/pipeline_runner/
├── pyproject.toml                    # Poetry project definition
├── Dockerfile                        # Zero-install container
├── pipeline_runner/
│   ├── cli.py                        # CLI entry point
│   ├── pipelines/
│   │   ├── document_processing.py    # Document ingestion flow
│   │   ├── indexing.py               # SQLite FTS5 index integrity
│   │   ├── reporting.py              # Daily report generation
│   │   ├── archgate_check.py         # ADR compliance validation
│   │   └── test_suite.py             # Full test suite (Elixir + Python)
│   └── runners/
│       └── docker.py                 # Docker-based step execution
└── tests/
    ├── test_runner.py                # Runner framework tests
    └── test_pipelines.py             # Pipeline structure + ADR validation
```

## Available Pipelines

### `pipeline document-processing`

Validates the full document ingestion flow: input → conversion → staging.

```bash
docker compose run --rm pipeline-runner document-processing --dry-run
```

| Flag | Description |
|------|-------------|
| `--dry-run` | Validate prerequisites without processing documents |

### `pipeline index-validation`

Checks SQLite FTS5 index integrity and relationship consistency.

```bash
docker compose run --rm pipeline-runner index-validation
```

| Flag | Description |
|------|-------------|
| `--full` | Run full reindex validation (slower) |

### `pipeline daily-report`

Generates or validates the daily report.

```bash
docker compose run --rm pipeline-runner daily-report
docker compose run --rm pipeline-runner daily-report --validate-only
```

### `pipeline archgate-check`

Validates the codebase against Architecture Decision Records.

```bash
docker compose run --rm pipeline-runner archgate-check
docker compose run --rm pipeline-runner archgate-check --staged   # pre-commit
docker compose run --rm pipeline-runner archgate-check --adr ARCH-001
```

### `pipeline test`

Runs the full test suite across Elixir and Python.

```bash
docker compose run --rm pipeline-runner test
docker compose run --rm pipeline-runner test --elixir-only
docker compose run --rm pipeline-runner test --python-only
```

## Pipeline Architecture

Each pipeline follows the same pattern:

1. **Define steps** — A list of `(name, command)` tuples
2. **Execute via runner** — `run_pipeline()` executes steps sequentially inside containers
3. **Fail fast** — If any step fails, the pipeline aborts
4. **Report result** — Summary printed with pass/fail counts

```python
from pipeline_runner.runners.docker import run_pipeline, exit_with_result

result = run_pipeline("My Pipeline", [
    ("Step 1", ["docker", "compose", "exec", "librarian", "mix", "test"]),
    ("Step 2", ["echo", "done"]),
])
exit_with_result(result)
```

## Adding a New Pipeline

1. Create `pipeline_runner/pipelines/my_pipeline.py`
2. Define a Click command with appropriate flags
3. Register it in `pipeline_runner/cli.py`
4. Add CLI help tests in `tests/test_pipelines.py`
5. Document it in this file

## CI/CD

Pipeline tests and ADR validation are integrated into GitHub Actions (`.github/workflows/ci.yml`).
The CI runs `ruff check`, `pytest`, `mix compile --warnings-as-errors`, `mix test`, ADR validation, and a sensitive data audit on every push/PR to `main`.

## Related

- `spec/TESTING.md` — Testing strategy and how pipelines fit in
- `spec/ARCHITECTURE.md` — System architecture
- `.archgate/adrs/ARCH-006-pipeline-testing.md` — ADR for testing policy
- `.github/workflows/ci.yml` — GitHub Actions CI/CD configuration
