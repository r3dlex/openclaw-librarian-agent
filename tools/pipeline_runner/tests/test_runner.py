"""Tests for the pipeline runner framework."""

from pipeline_runner.runners.docker import PipelineResult, StepResult, run_step


class TestStepResult:
    def test_successful_step(self):
        result = StepResult(name="test", success=True, output="ok")
        assert result.success
        assert result.name == "test"

    def test_failed_step(self):
        result = StepResult(name="test", success=False, error="boom")
        assert not result.success
        assert result.error == "boom"


class TestPipelineResult:
    def test_all_steps_pass(self):
        result = PipelineResult(
            name="test-pipeline",
            steps=[
                StepResult(name="step1", success=True),
                StepResult(name="step2", success=True),
            ],
        )
        assert result.success
        assert "PASSED" in result.summary()

    def test_one_step_fails(self):
        result = PipelineResult(
            name="test-pipeline",
            steps=[
                StepResult(name="step1", success=True),
                StepResult(name="step2", success=False, error="failed"),
            ],
        )
        assert not result.success
        assert "FAILED" in result.summary()
        assert "1/2" in result.summary()

    def test_empty_pipeline_passes(self):
        result = PipelineResult(name="empty")
        assert result.success

    def test_summary_format(self):
        result = PipelineResult(
            name="my-pipeline",
            steps=[StepResult(name="s", success=True)],
        )
        summary = result.summary()
        assert "my-pipeline" in summary
        assert "1/1" in summary


class TestRunStep:
    def test_successful_command(self):
        result = run_step("echo test", ["echo", "hello"])
        assert result.success
        assert "hello" in result.output

    def test_failed_command(self):
        result = run_step("false", ["false"])
        assert not result.success

    def test_nonexistent_command(self):
        result = run_step("missing", ["__nonexistent_cmd_12345__"])
        assert not result.success
        assert result.error
