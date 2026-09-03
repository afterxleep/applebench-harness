#!/usr/bin/env python3
"""Which tasks a model still owes, printed as a space-separated list.

Two kinds of debt, and both are answered without consulting git:

**New** — the task is in the scored set and the report has no run of it for
this model.

**Changed** — the report has a run, but the task is not the same task any more.
That is decided by hashing what the task actually is: its YAML, and the fixture
it runs against. A branch name cannot answer this; content can, and content
survives merges, rebases and renames.

A report records the fingerprint of every task it scored, alongside the export.
When the report predates fingerprints entirely, every task in it is treated as
unchanged rather than as changed — otherwise adopting this would re-run the
whole suite once, for nothing.

Usage:
    pending-tasks.py --model <id> [--report <path>] [--suite <path>]
                     [--mode both|new|changed]
"""
import argparse
import json
import os
import pathlib
import sys

def load_fingerprints() -> dict[str, str]:
    """Current fingerprints, via the same code the publisher records with."""
    import subprocess
    here = pathlib.Path(__file__).resolve().parent
    output = subprocess.run(
        [sys.executable, str(here / "task-fingerprints.py")],
        capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(output)


def suite_tasks(path: pathlib.Path) -> list[str]:
    tasks, in_tasks = [], False
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("tasks:"):
            in_tasks = True
            continue
        if not in_tasks:
            continue
        if stripped.startswith("- "):
            tasks.append(stripped[2:].strip())
        elif stripped and not stripped.startswith("#"):
            break
    return tasks


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--report")
    parser.add_argument("--suite")
    parser.add_argument("--mode", default="both", choices=["both", "new", "changed"])
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parents[1]
    taskset = pathlib.Path(os.environ.get("APPLEBENCH_TASKSET") or root)

    # Scored set: the named suite, or every gold suite there is.
    if args.suite:
        scored = set(suite_tasks(pathlib.Path(args.suite)))
    else:
        scored = set()
        for path in sorted((taskset / "Examples/Suites").glob("gold*.yaml")):
            scored.update(suite_tasks(path))
    if not scored:
        print("error: no scored tasks found", file=sys.stderr)
        return 1

    current = load_fingerprints()

    scored_before: dict[str, str] = {}
    if args.report and pathlib.Path(args.report).exists():
        report = json.loads(pathlib.Path(args.report).read_text())
        recorded = report.get("task_fingerprints") or {}
        for run in report.get("runs", []):
            if run.get("agent", {}).get("model") != args.model:
                continue
            task = run.get("task")
            # No recorded fingerprint means the report predates them. Treat the
            # task as unchanged so adopting this does not re-run everything.
            scored_before[task] = recorded.get(task, current.get(task, ""))

    new = sorted(t for t in scored if t not in scored_before)
    changed = sorted(
        t for t in scored
        if t in scored_before and current.get(t, "") != scored_before[t]
    )

    wanted = {"both": new + changed, "new": new, "changed": changed}[args.mode]
    print(" ".join(sorted(set(wanted))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
