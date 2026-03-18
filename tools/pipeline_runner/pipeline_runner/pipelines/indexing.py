"""Index validation pipeline — ensures SQLite FTS5 index integrity."""

import click

from pipeline_runner.runners.docker import exit_with_result, run_pipeline


@click.command("index-validation")
@click.option("--full", is_flag=True, help="Run full reindex validation (slower)")
def index_validation(full: bool):
    """Validate the document index integrity.

    Checks that the SQLite FTS5 index is consistent with the vault contents
    and that all relationships are valid.
    """
    db_check = (
        'Librarian.Repo'
        ' |> Ecto.Adapters.SQL.query!("SELECT count(*) FROM documents")'
        " |> IO.inspect()"
    )
    fts_check = (
        'Librarian.Repo'
        ' |> Ecto.Adapters.SQL.query!('
        "\"INSERT INTO documents_fts(documents_fts) VALUES('integrity-check')\")"
        " |> IO.inspect()"
    )
    rel_check = r"""
    Librarian.Repo
    |> Ecto.Adapters.SQL.query!(
      "SELECT COUNT(*) FROM relationships r " <>
      "LEFT JOIN documents d ON r.source_id = d.id WHERE d.id IS NULL"
    )
    |> then(fn %{rows: [[count]]} ->
      if count > 0,
        do: raise("\#{count} orphaned relationships"),
        else: IO.puts("OK: No orphaned relationships")
    end)
    """

    steps = [
        ("Verify database exists", [
            "docker", "compose", "exec", "librarian",
            "mix", "run", "-e", db_check,
        ]),
        ("Check FTS5 integrity", [
            "docker", "compose", "exec", "librarian",
            "mix", "run", "-e", fts_check,
        ]),
        ("Validate relationships", [
            "docker", "compose", "exec", "librarian",
            "mix", "run", "-e", rel_check,
        ]),
    ]

    if full:
        steps.append((
            "Full reindex",
            ["docker", "compose", "exec", "librarian", "mix", "run", "-e",
             "IO.puts(\"Full reindex not yet implemented\")"],
        ))

    result = run_pipeline("Index Validation", steps)
    exit_with_result(result)
