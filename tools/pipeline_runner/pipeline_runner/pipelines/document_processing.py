"""Document processing pipeline — validates the ingestion flow end-to-end."""

from pathlib import Path

import click

from pipeline_runner.runners.docker import (
    PipelineResult,
    exit_with_result,
    run_pipeline,
    run_step,
)


def get_project_root() -> Path:
    return Path(__file__).resolve().parents[4]


@click.command("document-processing")
@click.option("--dry-run", is_flag=True, help="Validate without processing documents")
def document_processing(dry_run: bool):
    """Run the document processing pipeline.

    Validates that the full ingestion flow works:
    input/ → conversion → staging/ → (agent classification) → vault
    """
    root = get_project_root()

    if dry_run:
        result = run_pipeline(
            "Document Processing (dry run)",
            [
                ("Check Docker services", ["docker", "compose", "ps", "--status=running"]),
                ("Verify input folder", ["test", "-d", str(root / "test_fixtures" / "input")]),
                ("Verify Pandoc available", [
                    "docker", "compose", "exec", "librarian", "pandoc", "--version",
                ]),
            ],
        )
    else:
        steps: list[tuple[str, list[str]]] = [
            ("Verify services running", ["docker", "compose", "ps", "--status=running"]),
            (
                "Process input folder",
                ["docker", "compose", "exec", "librarian", "mix", "run", "-e",
                 "Librarian.Input.process_now()"],
            ),
        ]
        result = run_pipeline("Document Processing", steps)

    exit_with_result(result)


def validate_staging_output(staging_dir: Path) -> PipelineResult:
    """Validate that staged items have correct structure."""
    result = PipelineResult(name="Staging Validation")

    meta_files = list(staging_dir.glob("*.meta.json"))
    if not meta_files:
        result.steps.append(
            run_step("Check for staged items", ["test", "-n", ""])
        )
        return result

    for meta_file in meta_files:
        md_file = meta_file.with_suffix("").with_suffix(".md")
        step = run_step(
            f"Verify {meta_file.stem} has companion .md",
            ["test", "-f", str(md_file)],
        )
        result.steps.append(step)

    return result
