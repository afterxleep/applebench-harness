#!/usr/bin/env python3
"""Says whether a fixture's graded tests are withheld from the agent.

Prints `isolate`, `tests-only` or `keep`.

Withholding is the default: a benchmark that hands the agent its own
assertions measures reading comprehension rather than diagnosis. It is off
for fixtures where a task legitimately needs the agent to change the project
or to author a test target — overlaying a pre-generated project back over
that work at grading time would discard the answer.

That is true of three kinds of task, so the rule is read off the task set
rather than kept as a list that drifts:

  * `project` — the defect is in the project configuration.
  * `ops` — the agent drives the toolchain and often regenerates the project.
  * `interaction` — the agent authors the UI test target that grades it.

A `project.solution.yml` says the same thing directly: the authored fix
changes the project, so the agent's project must survive to grading.

A fixture can also say how it is graded with a `withhold` file holding one
word, which overrides the rules above:

  * `isolate` — withhold the tests and the test targets (as above).
  * `tests-only` — withhold the test files but keep the project as the agent
    left it: at grading only `Tests/` and `UITests/` are overlaid, with no
    project regeneration. For a fix that lives partly in the project, where
    regenerating from the sealed spec would throw the answer away. The agent
    still sees the test target and its file names, never their contents.

Usage:
    fixture-isolation.py <FixtureName>
"""
import os
import pathlib
import re
import sys

KEEP_CATEGORIES = {"project", "ops", "interaction"}

# The tasks may live in a different repository from the harness. See
# Scripts/taskset.sh.
root = pathlib.Path(os.environ.get("APPLEBENCH_TASKSET") or pathlib.Path(__file__).resolve().parents[1])


def tasks_using(fixture):
    for path in sorted((root / "Examples/Tasks").glob("*.yaml")):
        text = path.read_text()
        url = re.search(r"^\s*url:\s*(\S+)\s*$", text, re.MULTILINE)
        if not url or url.group(1).rstrip("/").rsplit("/", 1)[-1] != fixture:
            continue
        category = re.search(r"^category:\s*(\S+)", text, re.MULTILINE)
        yield path.stem, (category.group(1) if category else "")


def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    fixture = sys.argv[1]

    marker = root / "Fixtures" / fixture / "withhold"
    if marker.exists():
        mode = marker.read_text().strip()
        if mode not in ("isolate", "tests-only"):
            print(f"error: {marker} must say isolate or tests-only, not {mode!r}", file=sys.stderr)
            return 2
        print(mode)
        return 0

    if (root / "Fixtures" / fixture / "project.solution.yml").exists():
        print("keep")
        return 0

    for _, category in tasks_using(fixture):
        if category in KEEP_CATEGORIES:
            print("keep")
            return 0

    print("isolate")
    return 0


if __name__ == "__main__":
    sys.exit(main())
