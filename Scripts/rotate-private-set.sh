#!/bin/bash
# Rotate a scoring task set's fixtures so leaked transcripts stop matching it.
#
# Keeping answers closed buys time against contamination; rotation is what
# keeps the benchmark alive past the first leak. This rewrites bundle IDs and
# copies the fixtures into .applebench/rotated/<seed>/ inside the harness
# clone, so the task set itself is never written to.
#
# The output is a seeded starting point, not a finished scoring set. Prompts,
# withheld tests and solution overlays still need a matching pass.
#
# Usage:
#   APPLEBENCH_TASKSET=/path/to/scoring-set ./Scripts/rotate-private-set.sh 2026-q4
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=Scripts/taskset.sh
. "$(dirname "$0")/taskset.sh"

seed="${1:-}"
if [ -z "$seed" ]; then
    echo "usage: $0 <seed>" >&2
    echo "example: $0 2026-q4" >&2
    exit 2
fi

safe_seed=$(printf '%s' "$seed" | tr -cs 'A-Za-z0-9' '-')
suffix=$(printf '%s' "$safe_seed" | tr '[:upper:]' '[:lower:]')
dest="$root/.applebench/rotated/$suffix"

python3 - "$taskset_root" "$dest" "$suffix" <<'PYTHON'
import pathlib
import re
import shutil
import sys

taskset = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
suffix = sys.argv[3]

gold_path = taskset / "Examples/Suites/gold.yaml"
if not gold_path.exists():
    print(
        "error: no Examples/Suites/gold.yaml in this task set, so nothing here "
        "is scored and nothing needs rotating.",
        file=sys.stderr,
    )
    raise SystemExit(1)

gold = [
    line.strip()[2:].strip()
    for line in gold_path.read_text().splitlines()
    if line.strip().startswith("- ")
]

fixtures = set()
for task_id in gold:
    text = (taskset / "Examples/Tasks" / f"{task_id}.yaml").read_text()
    fixtures.update(re.findall(r"\.applebench/fixtures/([A-Za-z0-9_]+)", text))

if dest.exists():
    shutil.rmtree(dest)
dest.mkdir(parents=True)

rewritten = 0
for name in sorted(fixtures):
    shutil.copytree(
        taskset / "Fixtures" / name,
        dest / name,
        ignore=shutil.ignore_patterns(".git"),
    )
    for path in (dest / name).rglob("*"):
        if not path.is_file() or path.suffix not in {".yml", ".yaml", ".swift", ".plist", ".md"}:
            continue
        text = path.read_text()
        updated = text.replace("com.applebench", f"com.applebench.{suffix}")
        if updated != text:
            path.write_text(updated)
            rewritten += 1

(dest / "README.md").write_text(
    f"""# Rotated fixtures ({suffix})

Copied from the scoring task set at `{taskset}`. Bundle IDs now use
`com.applebench.{suffix}`.

A rotation is not a scoring set until:

- user-visible copy and type names that appear in prompts are rewritten,
- solution overlays are regenerated with `./Scripts/make-solutions.sh`,
- task YAML `repository.url` points at these snapshots,
- and every task still holds the contract under `./Scripts/verify-tasks.sh`.

A rotation that skips the last one has replaced a leaked set with an unproven
one, which is worse.
"""
)

print(f"Rotated {len(fixtures)} fixtures to {dest}")
print(f"Rewrote bundle IDs in {rewritten} files")
print("Next: rewrite prompts, run ./Scripts/make-solutions.sh, then verify-tasks.sh")
PYTHON
