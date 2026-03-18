"""CLI entry point for the pipeline runner."""

import click

from pipeline_runner.pipelines.archgate_check import archgate_check
from pipeline_runner.pipelines.document_processing import document_processing
from pipeline_runner.pipelines.indexing import index_validation
from pipeline_runner.pipelines.reporting import daily_report
from pipeline_runner.pipelines.test_suite import test_suite


@click.group()
def main():
    """Openclaw Librarian Agent — Pipeline Runner."""


main.add_command(document_processing)
main.add_command(index_validation)
main.add_command(daily_report)
main.add_command(archgate_check)
main.add_command(test_suite)


if __name__ == "__main__":
    main()
