"""Tests for pipeline definitions — validates structure and CLI wiring."""

from pathlib import Path

import yaml
from click.testing import CliRunner

from pipeline_runner.cli import main


class TestCLIStructure:
    def test_main_group_has_all_commands(self):
        runner = CliRunner()
        result = runner.invoke(main, ["--help"])
        assert result.exit_code == 0
        assert "document-processing" in result.output
        assert "index-validation" in result.output
        assert "daily-report" in result.output
        assert "archgate-check" in result.output
        assert "test" in result.output

    def test_document_processing_help(self):
        runner = CliRunner()
        result = runner.invoke(main, ["document-processing", "--help"])
        assert result.exit_code == 0
        assert "--dry-run" in result.output

    def test_index_validation_help(self):
        runner = CliRunner()
        result = runner.invoke(main, ["index-validation", "--help"])
        assert result.exit_code == 0
        assert "--full" in result.output

    def test_daily_report_help(self):
        runner = CliRunner()
        result = runner.invoke(main, ["daily-report", "--help"])
        assert result.exit_code == 0
        assert "--validate-only" in result.output

    def test_archgate_check_help(self):
        runner = CliRunner()
        result = runner.invoke(main, ["archgate-check", "--help"])
        assert result.exit_code == 0
        assert "--staged" in result.output
        assert "--adr" in result.output

    def test_test_suite_help(self):
        runner = CliRunner()
        result = runner.invoke(main, ["test", "--help"])
        assert result.exit_code == 0
        assert "--elixir-only" in result.output
        assert "--python-only" in result.output


class TestADRFrontmatter:
    """Validates that all committed ADRs have valid frontmatter."""

    def _get_adrs_dir(self) -> Path:
        return Path(__file__).resolve().parents[3] / ".archgate" / "adrs"

    def test_all_adrs_have_valid_frontmatter(self):
        adrs_dir = self._get_adrs_dir()
        if not adrs_dir.exists():
            return  # Skip if no ADRs yet

        for adr_file in sorted(adrs_dir.glob("*.md")):
            text = adr_file.read_text()
            assert text.startswith("---"), f"{adr_file.name}: missing frontmatter"
            parts = text.split("---", 2)
            assert len(parts) >= 3, f"{adr_file.name}: malformed frontmatter"
            meta = yaml.safe_load(parts[1])
            assert "id" in meta, f"{adr_file.name}: missing 'id'"
            assert "title" in meta, f"{adr_file.name}: missing 'title'"
            assert "domain" in meta, f"{adr_file.name}: missing 'domain'"
            assert "rules" in meta, f"{adr_file.name}: missing 'rules'"

    def test_adr_ids_match_filenames(self):
        adrs_dir = self._get_adrs_dir()
        if not adrs_dir.exists():
            return

        for adr_file in sorted(adrs_dir.glob("*.md")):
            text = adr_file.read_text()
            parts = text.split("---", 2)
            if len(parts) < 3:
                continue
            meta = yaml.safe_load(parts[1])
            adr_id = meta.get("id", "")
            assert adr_file.name.startswith(adr_id), (
                f"{adr_file.name}: filename should start with id '{adr_id}'"
            )
