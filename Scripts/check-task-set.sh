#!/bin/bash
# Asserts the shape of the shipped task set.
#
# AppleBench is not a filled difficulty grid. It is a gold scoring set plus
# a small public-dev subset that is expected to leak and is never scored.
# This script checks that partition, that every task YAML is well-formed,
# and that every referenced fixture still exists.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=Scripts/taskset.sh
. "$(dirname "$0")/taskset.sh"
tasks_dir="${1:-$taskset_tasks}"

python3 - "$taskset_root" "$tasks_dir" <<'PYTHON'
import pathlib
import re
import sys

CATEGORIES = [
    "build", "tests", "runtime", "visual", "interaction",
    "project", "frameworks", "ops",
]
DIFFICULTIES = list(range(1, 11))

root = pathlib.Path(sys.argv[1])
tasks_dir = pathlib.Path(sys.argv[2])
files = sorted(tasks_dir.glob("*.yaml"))

def scalar(text, key):
    match = re.search(rf"^{key}:[ \t]*(.+?)[ \t]*$", text, re.MULTILINE)
    return match.group(1).strip().strip('"\'') if match else None

def suite_ids(path):
    ids = []
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            ids.append(stripped[2:].strip().strip('"\''))
    return ids

problems = []
grid = {category: {} for category in CATEGORIES}
task_ids = []
fixture_names = set()

for path in files:
    text = path.read_text()
    task_id = scalar(text, "id")
    category = scalar(text, "category")
    difficulty = scalar(text, "difficulty")
    task_ids.append(task_id)

    if task_id != path.stem:
        problems.append(f"{path.name}: id '{task_id}' does not match the file name")
    if category not in CATEGORIES:
        problems.append(f"{path.name}: category '{category}' is not one of {', '.join(CATEGORIES)}")
        continue
    try:
        difficulty = int(difficulty)
    except (TypeError, ValueError):
        problems.append(f"{path.name}: difficulty '{difficulty}' is not an integer")
        continue
    if difficulty not in DIFFICULTIES:
        problems.append(f"{path.name}: difficulty {difficulty} is outside 1-10")
        continue
    grid[category].setdefault(difficulty, []).append(path.stem)

    for line in text.splitlines():
        if "fixtures/" in line:
            fixture_names.add(line.split("fixtures/")[-1].strip())

gold_path = root / "Examples/Suites/gold.yaml"
dev_path = root / "Examples/Suites/dev.yaml"
gold = suite_ids(gold_path) if gold_path.exists() else []
dev = suite_ids(dev_path) if dev_path.exists() else []
gold_set, dev_set, all_set = set(gold), set(dev), set(task_ids)

if gold_path.exists() and dev_path.exists():
    overlap = sorted(gold_set & dev_set)
    if overlap:
        problems.append(f"gold and dev both contain: {', '.join(overlap)}")
    missing = sorted(all_set - gold_set - dev_set)
    if missing:
        problems.append(f"tasks in neither gold nor dev: {', '.join(missing)}")
    extra_gold = sorted(gold_set - all_set)
    if extra_gold:
        problems.append(f"gold.yaml references unknown tasks: {', '.join(extra_gold)}")
    extra_dev = sorted(dev_set - all_set)
    if extra_dev:
        problems.append(f"dev.yaml references unknown tasks: {', '.join(extra_dev)}")
    if not (8 <= len(dev) <= 10):
        problems.append(f"dev subset must be 8-10 tasks, found {len(dev)}")
elif dev_path.exists() and not gold_path.exists():
    extra_dev = sorted(dev_set - all_set)
    if extra_dev:
        problems.append(f"dev.yaml references unknown tasks: {', '.join(extra_dev)}")
    missing = sorted(all_set - dev_set)
    if missing:
        problems.append(f"public tree has tasks not in dev.yaml: {', '.join(missing)}")
    print("gold suite not present; treating this tree as the public-dev subset.\n")
else:
    problems.append("missing Examples/Suites/dev.yaml")

for name in sorted(fixture_names):
    if not (root / "Fixtures" / name).is_dir():
        problems.append(f"referenced fixture is missing: Fixtures/{name}")

width = max(len(c) for c in CATEGORIES) + 2
print(f"AppleBench - task set in {tasks_dir}\n")
print(f"{len(files)} tasks  ·  gold {len(gold)}  ·  public-dev {len(dev)}\n")
header = " " * width + "".join(f"{d:<14}" for d in DIFFICULTIES)
print(header)
for category in CATEGORIES:
    cells = []
    for difficulty in DIFFICULTIES:
        found = grid[category].get(difficulty, [])
        cells.append((",".join(found) if found else "-")[:13].ljust(14))
    print(f"{category:<{width}}{''.join(cells)}")
print()

if problems:
    print(f"{len(problems)} problem(s):")
    for problem in problems:
        print(f"  - {problem}")
    sys.exit(1)

print(
    f"{len(files)} tasks partitioned into gold ({len(gold)}) "
    f"and public-dev ({len(dev)}). Categories: {', '.join(CATEGORIES)}."
)
PYTHON
