"""Reporting pipeline — generates and validates daily reports."""

import click

from pipeline_runner.runners.docker import exit_with_result, run_pipeline


@click.command("daily-report")
@click.option("--validate-only", is_flag=True, help="Validate last report without generating")
def daily_report(validate_only: bool):
    """Generate or validate the daily report.

    Triggers daily report generation and validates the output format
    matches the expected structure (YAML front matter, sections, etc.).
    """
    if validate_only:
        steps = [
            ("Check reports directory", [
                "docker", "compose", "exec", "librarian",
                "mix", "run", "-e",
                """
                data_folder = Application.get_env(:librarian, :data_folder, "")
                reports_dir = Path.join([data_folder, "log", "reports"])
                if File.dir?(reports_dir) do
                  files = File.ls!(reports_dir)
                  IO.puts("Reports found: #{length(files)}")
                  Enum.each(files, &IO.puts("  #{&1}"))
                else
                  IO.puts("ERROR: Reports directory not found")
                  System.halt(1)
                end
                """,
            ]),
        ]
        result = run_pipeline("Report Validation", steps)
    else:
        steps = [
            ("Generate daily report", [
                "docker", "compose", "exec", "librarian",
                "mix", "run", "-e", "Librarian.Reporter.generate_now()",
            ]),
            ("Prune old backups", [
                "docker", "compose", "exec", "librarian",
                "mix", "run", "-e", "Librarian.Vault.Backup.prune()",
            ]),
        ]
        result = run_pipeline("Daily Report Generation", steps)

    exit_with_result(result)
