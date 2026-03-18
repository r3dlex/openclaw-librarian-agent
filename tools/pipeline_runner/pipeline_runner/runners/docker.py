"""Docker-based pipeline runner for zero-install execution."""

import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from rich.console import Console

console = Console()


@dataclass
class StepResult:
    name: str
    success: bool
    output: str = ""
    error: str = ""


@dataclass
class PipelineResult:
    name: str
    steps: list[StepResult] = field(default_factory=list)

    @property
    def success(self) -> bool:
        return all(s.success for s in self.steps)

    def summary(self) -> str:
        passed = sum(1 for s in self.steps if s.success)
        total = len(self.steps)
        status = "PASSED" if self.success else "FAILED"
        return f"Pipeline '{self.name}': {status} ({passed}/{total} steps)"


def run_step(name: str, cmd: list[str], cwd: str | Path | None = None) -> StepResult:
    """Run a single pipeline step and return the result."""
    console.print(f"  [bold blue]→[/] {name}")
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=cwd,
            timeout=300,
        )
        success = result.returncode == 0
        if success:
            console.print(f"  [bold green]✓[/] {name}")
        else:
            console.print(f"  [bold red]✗[/] {name}")
            if result.stderr:
                console.print(f"    [dim]{result.stderr.strip()[:200]}[/]")
        return StepResult(
            name=name,
            success=success,
            output=result.stdout,
            error=result.stderr,
        )
    except subprocess.TimeoutExpired:
        console.print(f"  [bold red]✗[/] {name} (timeout)")
        return StepResult(name=name, success=False, error="Step timed out after 300s")
    except FileNotFoundError as e:
        console.print(f"  [bold red]✗[/] {name} (command not found)")
        return StepResult(name=name, success=False, error=str(e))


def docker_compose_run(
    service: str, command: list[str], project_root: str | Path | None = None
) -> StepResult:
    """Run a command inside a docker compose service."""
    cmd = ["docker", "compose", "run", "--rm", service, *command]
    return run_step(
        name=f"docker:{service} {' '.join(command)}", cmd=cmd, cwd=project_root
    )


def run_pipeline(name: str, steps: list[tuple[str, list[str]]]) -> PipelineResult:
    """Execute a sequence of named steps and return the aggregate result."""
    console.print(f"\n[bold]Pipeline: {name}[/]")
    console.print("─" * 40)
    result = PipelineResult(name=name)
    for step_name, cmd in steps:
        step = run_step(step_name, cmd)
        result.steps.append(step)
        if not step.success:
            console.print(f"\n[bold red]Pipeline aborted: step '{step_name}' failed[/]")
            break
    console.print(f"\n{result.summary()}")
    return result


def exit_with_result(result: PipelineResult) -> None:
    """Exit the process with appropriate code based on pipeline result."""
    sys.exit(0 if result.success else 1)
