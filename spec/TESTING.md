# Testing

> Testing strategy for the Openclaw Librarian Agent.
> All tests run inside Docker containers (zero-install).

## Test Layers

| Layer | Tool | Location | What it tests |
|-------|------|----------|--------------|
| **Unit (Elixir)** | `mix test` | `test/*.exs` | Individual modules: Processor, Indexer, Staging, Backup, Watcher |
| **Unit (Python)** | `pytest` | `tools/pipeline_runner/tests/` | Pipeline runner framework, CLI wiring, ADR validation |
| **Integration** | Pipeline runner | `pipeline document-processing --dry-run` | End-to-end document flow through Docker services |
| **ADR compliance** | Pipeline runner | `pipeline archgate-check` | Codebase against architectural decisions in `.archgate/adrs/` |
| **Index integrity** | Pipeline runner | `pipeline index-validation` | SQLite FTS5 consistency and relationship validity |

## Running Tests

### Full suite (recommended)

```bash
docker compose run --rm pipeline-runner test
```

### Elixir only

```bash
docker compose exec librarian mix test
# or via pipeline:
docker compose run --rm pipeline-runner test --elixir-only
```

### Python only

```bash
docker compose run --rm pipeline-runner test --python-only
```

### ADR compliance

```bash
docker compose run --rm pipeline-runner archgate-check
```

### Local Python tests (without Docker)

For faster iteration during development of the pipeline runner:

```bash
cd tools/pipeline_runner
poetry install
poetry run pytest
poetry run ruff check .
```

## Test Requirements

### For Elixir modules

- Every module in `lib/librarian/` must have corresponding tests in `test/`
- Tests should be runnable with `mix test` inside the Docker container
- Use `Ecto.Adapters.SQL.Sandbox` for database tests

### For Python pipelines

- Every pipeline command must have a `--help` test in `test_pipelines.py`
- The runner framework (`StepResult`, `PipelineResult`, `run_step`) must have unit tests
- ADR frontmatter validation runs as a Python test (catches structural issues early)

### For ADRs

- All ADRs in `.archgate/adrs/` must have valid YAML frontmatter with `id`, `title`, `domain`, `rules`
- ADR filenames must start with their `id` field
- ADRs with `rules: true` should have companion `.rules.ts` files (when archgate is fully adopted)

## What to Test When Adding Features

| Change | Required tests |
|--------|---------------|
| New Elixir module (e.g., Notifier) | Unit test in `test/` |
| New pipeline | CLI help test + functional test in `tests/test_pipelines.py` |
| New ADR | Frontmatter validated automatically by `TestADRFrontmatter` |
| Schema migration | Integration test verifying the migration runs |
| Vault structure change | Update `spec/STRUCTURE.md`, add Elixir test for new structure |

## Coverage

- **Python**: pytest-cov reports coverage on every run (configured in `pyproject.toml`)
- **Elixir**: Add `excoveralls` to `mix.exs` when coverage reporting is needed

## CI/CD Integration

GitHub Actions runs automatically on every push/PR to `main`. See `.github/workflows/ci.yml`.

The CI pipeline runs these jobs in parallel:
- **python-tests** — ruff lint + pytest for the pipeline runner
- **elixir-compile** — `mix compile --warnings-as-errors`
- **elixir-tests** — `mix test`
- **archgate-check** — ADR frontmatter validation via pytest
- **docker-build** — ensures both Docker images build successfully
- **sensitive-data-check** — scans for emails, API keys, absolute paths in committed files

The `pipeline test` command also exits with code 1 on any failure, making it suitable for local CI:

```bash
docker compose run --rm pipeline-runner test
```

## Related

- `spec/PIPELINES.md` — Pipeline definitions and usage
- `.archgate/adrs/ARCH-006-pipeline-testing.md` — ADR for testing policy
- `.github/workflows/ci.yml` — GitHub Actions CI/CD configuration
- `tools/pipeline_runner/pyproject.toml` — Python test configuration
