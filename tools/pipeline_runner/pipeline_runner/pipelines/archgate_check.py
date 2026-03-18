"""Archgate ADR compliance pipeline — validates codebase against architectural decisions."""

from pathlib import Path

import click

from pipeline_runner.runners.docker import exit_with_result, run_pipeline


def get_project_root() -> Path:
    return Path(__file__).resolve().parents[4]


@click.command("archgate-check")
@click.option("--staged", is_flag=True, help="Only check staged files (for pre-commit hooks)")
@click.option("--adr", type=str, default=None, help="Check a specific ADR by ID (e.g., ARCH-001)")
def archgate_check(staged: bool, adr: str | None):
    """Run archgate ADR compliance checks.

    Validates the codebase against all Architecture Decision Records
    with `rules: true` in .archgate/adrs/.
    """
    root = get_project_root()
    adrs_dir = root / ".archgate" / "adrs"

    # First verify ADRs exist
    adr_files = list(adrs_dir.glob("*.md")) if adrs_dir.exists() else []
    if not adr_files:
        click.echo("No ADRs found in .archgate/adrs/. Run 'archgate init' first.")
        raise SystemExit(1)

    steps: list[tuple[str, list[str]]] = [
        ("Verify archgate directory", ["test", "-d", str(adrs_dir)]),
    ]

    # Check ADR frontmatter validity
    steps.append((
        "Validate ADR frontmatter",
        ["python", "-c", _frontmatter_check_script(adrs_dir)],
    ))

    # Run archgate check if installed, otherwise validate structurally
    cmd = ["npx", "archgate", "check"]
    if staged:
        cmd.append("--staged")
    if adr:
        cmd.extend(["--adr", adr])

    steps.append(("Run archgate check", cmd))

    result = run_pipeline("Archgate ADR Compliance", steps)
    exit_with_result(result)


def _frontmatter_check_script(adrs_dir: Path) -> str:
    """Generate a Python script that validates ADR frontmatter."""
    return f"""
import yaml, sys, pathlib
adrs_dir = pathlib.Path("{adrs_dir}")
errors = []
for f in sorted(adrs_dir.glob("*.md")):
    text = f.read_text()
    if not text.startswith("---"):
        errors.append(f"{{f.name}}: missing YAML frontmatter")
        continue
    parts = text.split("---", 2)
    if len(parts) < 3:
        errors.append(f"{{f.name}}: malformed frontmatter")
        continue
    try:
        meta = yaml.safe_load(parts[1])
    except yaml.YAMLError as e:
        errors.append(f"{{f.name}}: invalid YAML: {{e}}")
        continue
    for field in ["id", "title", "domain", "rules"]:
        if field not in meta:
            errors.append(f"{{f.name}}: missing required field '{{field}}'")
if errors:
    for e in errors:
        print(f"ERROR: {{e}}", file=sys.stderr)
    sys.exit(1)
print(f"OK: {{len(list(adrs_dir.glob('*.md')))}} ADRs validated")
"""
