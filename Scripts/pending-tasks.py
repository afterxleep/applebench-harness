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


def modified_dates() -> dict[str, str]:
    """`modified:` from each task file, as an ISO date."""
    import os, re
    taskset = pathlib.Path(os.environ.get("APPLEBENCH_TASKSET") or pathlib.Path(__file__).resolve().parents[1])
    dates = {}
    for path in sorted((taskset / "Examples/Tasks").glob("*.yaml")):
        found = re.search(r"^modified:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})", path.read_text(), re.MULTILINE)
        if found:
            dates[path.stem] = found.group(1)
    return dates


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
    parser.add_argument("--report", help="Report to compare against. Defaults to the newest one that scored this model.")
    parser.add_argument("--reports-dir", default=None)
    parser.add_argument("--suite")
    parser.add_argument("--mode", default="both", choices=["both", "new", "changed"],
                        help="Kept for inspection; the runner always asks for both.")
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

    # Picking the newest report outright would compare a model against another
    # model's run and report every task as new. The default is the newest report
    # that actually scored *this* model.
    report_path = pathlib.Path(args.report) if args.report else None
    if report_path is None:
        directory = pathlib.Path(args.reports_dir or (root / "Reports"))
        # Both shapes count: a published report (Reports/<slug>.json) and a
        # raw run (Reports/<suite>-<date>/summary.json). A run that has not
        # been published is still a run, and treating it as absent would
        # re-run everything it already covered.
        candidates = sorted(
            list(directory.glob("*.json")) + list(directory.glob("*/summary.json")),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        for candidate in candidates:
            try:
                document = json.loads(candidate.read_text())
            except (ValueError, OSError):
                continue
            if any(r.get("agent", {}).get("model") == args.model for r in document.get("runs", [])):
                report_path = candidate
                break

    # When each task was last run for this model. A run id starts with its UTC
    # timestamp, so the date is the first ten characters.
    last_run: dict[str, str] = {}
    scored_before: dict[str, str] = {}
    if report_path and report_path.exists():
        print(f"comparing against {report_path.name}", file=sys.stderr)
        report = json.loads(report_path.read_text())
        recorded = report.get("task_fingerprints") or {}
        for run in report.get("runs", []):
            if run.get("agent", {}).get("model") != args.model:
                continue
            task = run.get("task")
            # No recorded fingerprint means the report predates them. Treat the
            # task as unchanged so adopting this does not re-run everything.
            scored_before[task] = recorded.get(task, current.get(task, ""))
            when = str(run.get("run_id", ""))[:10]
            if when and when > last_run.get(task, ""):
                last_run[task] = when

    new = sorted(t for t in scored if t not in scored_before)
    # A task with a `modified:` date is compared on dates: it needs re-running
    # when it changed after it was last run. One without falls back to the
    # content fingerprint, so an unstamped task is still covered.
    modified = modified_dates()
    changed = []
    for task in sorted(scored):
        if task not in scored_before:
            continue
        if task in modified:
            if modified[task] > last_run.get(task, ""):
                changed.append(task)
        elif current.get(task, "") != scored_before[task]:
            changed.append(task)

    wanted = {"both": new + changed, "new": new, "changed": changed}[args.mode]
    print(" ".join(sorted(set(wanted))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
