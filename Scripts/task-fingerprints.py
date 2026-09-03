#!/usr/bin/env python3
"""What each task currently *is*, as a content hash.

A task is its prompt, its graders and the fixture they run against, so a
fingerprint over those three answers the only question that matters when
deciding what to re-run: has this task changed since it was last scored?

This exists so that question never has to be asked of git. Branches, merges and
rebases all move a task's history around without changing the task, and a
diff against a branch name stops meaning anything the moment the branch is
merged or renamed. Content does not have that problem.

Usage:
    task-fingerprints.py                 # every task in the task set
    task-fingerprints.py <task-id> ...   # only these
"""
import hashlib
import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(os.environ.get("APPLEBENCH_TASKSET") or pathlib.Path(__file__).resolve().parents[1])

# Authoring files never reach the agent, so a change to one does not change the
# task. The reference fix is deliberately included: a fixture whose solution
# changed is a fixture whose contract may have changed with it.
IGNORED = {".DS_Store"}


def digest_of(path: pathlib.Path) -> str:
    sha = hashlib.sha256()
    if path.is_file():
        sha.update(path.read_bytes())
        return sha.hexdigest()
    for entry in sorted(p for p in path.rglob("*") if p.is_file()):
        if entry.name in IGNORED:
            continue
        sha.update(str(entry.relative_to(path)).encode())
        sha.update(entry.read_bytes())
    return sha.hexdigest()


def fixture_of(task_file: pathlib.Path) -> str:
    found = re.search(r"^\s*url:\s*(\S+)\s*$", task_file.read_text(), re.MULTILINE)
    if not found:
        return ""
    return found.group(1).rstrip("/").rsplit("/", 1)[-1]


def fingerprints(wanted: list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for task_file in sorted((ROOT / "Examples/Tasks").glob("*.yaml")):
        identifier = task_file.stem
        if wanted and identifier not in wanted:
            continue
        sha = hashlib.sha256()
        sha.update(digest_of(task_file).encode())
        fixture = ROOT / "Fixtures" / fixture_of(task_file)
        if fixture.is_dir():
            sha.update(digest_of(fixture).encode())
        result[identifier] = sha.hexdigest()
    return result


def main() -> int:
    print(json.dumps(fingerprints(sys.argv[1:]), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
