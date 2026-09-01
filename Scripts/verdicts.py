#!/usr/bin/env python3
"""Reads the verdict of the most recent run of each task from the run log.

`verify-tasks.sh` prints its table when it finishes, which is no help while a
long sweep is still going. This reads the same facts out of the run
directories, so progress is visible without waiting for the sweep to end.

Usage:
    verdicts.py                 # every task that has ever run
    verdicts.py ui-auto         # tasks whose id contains this
"""
import json
import pathlib
import re
import sys

RUNS = pathlib.Path(__file__).resolve().parents[1] / ".applebench/runs"
pattern = sys.argv[1] if len(sys.argv) > 1 else ""

latest: dict[tuple[str, str], pathlib.Path] = {}
for directory in sorted(RUNS.glob("*")):
    match = re.match(r".+?-([a-z]+[a-z-]*-\d+)-(fake|solution)$", directory.name)
    if match and pattern in match.group(1):
        latest[(match.group(1), match.group(2))] = directory


def verdict(directory: pathlib.Path) -> str:
    events = directory / "events.jsonl"
    if not events.exists():
        return "no-events"
    graders = [
        json.loads(line).get("payload", {})
        for line in events.read_text().splitlines()
        if json.loads(line).get("type") == "grader_finished"
    ]
    if not graders:
        return "incomplete"
    return "PASS" if all(g.get("passed") for g in graders) else "FAIL"


tasks = sorted({task for task, _ in latest})
broken = 0
for task in tasks:
    fake = verdict(latest[(task, "fake")]) if (task, "fake") in latest else "-"
    solution = verdict(latest[(task, "solution")]) if (task, "solution") in latest else "-"
    ok = fake == "FAIL" and solution == "PASS"
    broken += 0 if ok else 1
    print(f"{task:18} fake={fake:11} solution={solution:11} {'ok' if ok else 'BROKEN'}")

print(f"\n{len(tasks) - broken}/{len(tasks)} hold the contract")
