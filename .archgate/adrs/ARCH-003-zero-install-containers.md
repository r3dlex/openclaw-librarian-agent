---
id: ARCH-003
title: Zero-Install Policy via Containers
domain: architecture
rules: true
files: ["Dockerfile", "tools/pipeline_runner/Dockerfile", "docker-compose.yml"]
---

# ARCH-003: Zero-Install Policy via Containers

## Context

The project uses Elixir, Python, Pandoc, Tesseract OCR, and archgate. Requiring users to install all of these locally creates friction and "works on my machine" issues.

## Decision

All tooling runs inside Docker containers. The only prerequisites are Docker and Docker Compose. No local Elixir, Python, Pandoc, or Node.js installation required.

| Component | Container | Base Image |
|-----------|-----------|------------|
| Elixir service | `librarian` | `elixir:1.18-otp-27-alpine` |
| Pipeline runner | `pipeline-runner` | `python:3.12-alpine` |
| Pandoc / OCR | Inside `librarian` | Alpine packages |

### Do's and Don'ts

- **Do** use `docker compose run` or `docker compose exec` for all commands
- **Do** include all runtime dependencies in Dockerfiles
- **Do** keep Dockerfiles multi-stage for smaller images
- **Don't** add installation instructions for local tooling
- **Don't** require `mix`, `poetry`, or `npx` to be installed locally

## Compliance and Enforcement

### Automated rules
- Verify that `Dockerfile` and `tools/pipeline_runner/Dockerfile` exist
- Verify that `docker-compose.yml` defines both `librarian` and `pipeline-runner` services

## Consequences

**Positive:** Reproducible builds, no local setup friction, CI/CD parity.
**Negative:** Docker overhead, slower iteration for developers who prefer local.
