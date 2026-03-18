"""Test suite pipeline — runs all tests across Elixir and Python."""

import click

from pipeline_runner.runners.docker import exit_with_result, run_pipeline


@click.command("test")
@click.option("--elixir-only", is_flag=True, help="Only run Elixir tests")
@click.option("--python-only", is_flag=True, help="Only run Python pipeline tests")
def test_suite(elixir_only: bool, python_only: bool):
    """Run the full test suite.

    Executes Elixir tests (mix test) and Python pipeline tests (pytest)
    in their respective Docker containers.
    """
    steps: list[tuple[str, list[str]]] = []

    if not python_only:
        steps.extend([
            ("Compile Elixir (warnings as errors)", [
                "docker", "compose", "exec", "librarian",
                "mix", "compile", "--warnings-as-errors",
            ]),
            ("Run Elixir tests", [
                "docker", "compose", "exec", "librarian",
                "mix", "test",
            ]),
        ])

    if not elixir_only:
        steps.extend([
            ("Lint Python (ruff)", [
                "docker", "compose", "run", "--rm", "pipeline-runner",
                "ruff", "check", ".",
            ]),
            ("Run Python tests", [
                "docker", "compose", "run", "--rm", "pipeline-runner",
                "pytest",
            ]),
        ])

    if not steps:
        click.echo("Nothing to run — both --elixir-only and --python-only specified.")
        raise SystemExit(1)

    result = run_pipeline("Full Test Suite", steps)
    exit_with_result(result)
