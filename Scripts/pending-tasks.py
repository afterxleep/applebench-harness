#!/usr/bin/env python3
"""Which tasks a model still owes, printed as a space-separated list.

Two kinds of debt, and both are answered without consulting git:

**New** — the task is in the scored set and the report has no run of it for
this model.

**Changed** — the report has a run of it, but the task's `modified:` date is
newer than the day that run happened.

Usage:
    pending-tasks.py --model <id> [--report <path>] [--suite <path>]
                     [--mode both|new|changed]
"""

# Annotations are deferred so these run under the system python3 (3.9),
# which has no `X | None` type syntax. The scripts are called by shebang, so
# whichever python3 is first on PATH is the one that has to cope.
from __future__ import annotations
import argparse
import json
import os
import pathlib
import re
import sys


def parse_stamp(value: str) -> "datetime.datetime":
    """A `modified:` value as an instant in UTC.

    A bare date is read as the end of that day. A task edited and run on the
    same day cannot be told apart from one edited before the run, so the safe
    reading is that the edit came last and the task is still due. A timestamp
    says exactly when, and is compared exactly.
    """
    import datetime
    text = value.strip().strip('"').strip("'")
    if re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", text):
        return datetime.datetime.fromisoformat(text + "T23:59:59+00:00").astimezone(datetime.timezone.utc)
    text = text.replace("Z", "+00:00")
    if "T" not in text and " " in text:
        text = text.replace(" ", "T", 1)
    stamp = datetime.datetime.fromisoformat(text)
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=datetime.timezone.utc)
    return stamp.astimezone(datetime.timezone.utc)


def modified_stamps() -> dict[str, "datetime.datetime"]:
    """`modified:` from each task file, as an instant."""
    import os
    taskset = pathlib.Path(os.environ.get("APPLEBENCH_TASKSET") or pathlib.Path(__file__).resolve().parents[1])
    stamps = {}
    for path in sorted((taskset / "Examples/Tasks").glob("*.yaml")):
        found = re.search(r"^modified:\s*(\S+)", path.read_text(), re.MULTILINE)
        if found:
            try:
                stamps[path.stem] = parse_stamp(found.group(1))
            except ValueError:
                print(f"warning: {path.name}: unreadable modified: {found.group(1)!r}", file=sys.stderr)
    return stamps


def run_started(run_id: str) -> "datetime.datetime | None":
    """When a run began, from its id: `2026-09-06T160906-<task>-<agent>`, in UTC."""
    import datetime
    found = re.match(r"([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})", run_id)
    if not found:
        return None
    day, hh, mm, ss = found.groups()
    return datetime.datetime.fromisoformat(f"{day}T{hh}:{mm}:{ss}+00:00")


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
        # A published report is the complete cumulative record for a model.
        # A nested summary is one invocation and may contain only a handful of
        # tasks. Prefer the published record even when a partial summary was
        # written more recently, otherwise --changed reruns already-scored work.
        candidate_groups = [
            list(directory.glob("*.json")),
            list(directory.glob("*/summary.json")),
        ]
        for candidates in candidate_groups:
            for candidate in sorted(candidates, key=lambda p: p.stat().st_mtime, reverse=True):
                try:
                    document = json.loads(candidate.read_text())
                except (ValueError, OSError):
                    continue
                if any(r.get("agent", {}).get("model") == args.model for r in document.get("runs", [])):
                    report_path = candidate
                    break
            if report_path is not None:
                break

    # When each task was last run for this model, from the run id's UTC stamp.
    last_run: dict = {}
    scored_before: set[str] = set()
    if report_path and report_path.exists():
        print(f"comparing against {report_path.name}", file=sys.stderr)
        report = json.loads(report_path.read_text())
        for run in report.get("runs", []):
            if run.get("agent", {}).get("model") != args.model:
                continue
            task = run.get("task")
            # No recorded fingerprint means the report predates them. Treat the
            # task as unchanged so adopting this does not re-run everything.
            scored_before.add(task)
            when = run_started(str(run.get("run_id", "")))
            if when and (task not in last_run or when > last_run[task]):
                last_run[task] = when

    new = sorted(t for t in scored if t not in scored_before)
    # A task states when it was created or last updated, and needs running
    # again when that instant is later than this model's last run of it.
    #
    # A bare date is read as the end of its day: a task edited and run on the
    # same day cannot be told apart from one edited before the run, so it is
    # taken to be still due. A timestamp is exact, and a task edited at 17:41
    # and run at 18:09 is done.
    #
    # A task with no date at all always runs. The date is what says a task has
    # been checked; its absence says nobody has vouched for this one yet.
    modified = modified_stamps()
    changed = [
        task for task in sorted(scored)
        if task in scored_before
        and (task not in modified or task not in last_run or modified[task] > last_run[task])
    ]

    wanted = {"both": new + changed, "new": new, "changed": changed}[args.mode]
    print(" ".join(sorted(set(wanted))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
