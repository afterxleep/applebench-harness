#!/bin/bash
# Asserts that no fixture hands the agent its own answer.
#
# `prepare-fixtures.sh` strips the authoring files — project*.yml, README.md,
# .solution/, solution.patch — but it cannot strip a comment. A `// BUG:` line
# sitting on the defective statement ships to the agent verbatim and turns a
# diagnosis task into a reading-comprehension task.
#
# This scans every file that survives the snapshot and fails on any comment
# that names the planted defect or its fix. The place to document a defect is
# the fixture's README.md, which the pipeline already removes.
set -euo pipefail

# `--sources-only` checks the authored fixtures and skips the prepared
# snapshots. prepare-fixtures.sh uses it: the snapshot half describes state
# that only a prepare can produce, so gating a prepare on it would deadlock.
sources_only=false
if [ "${1:-}" = "--sources-only" ]; then
    sources_only=true
    shift
fi

root="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=Scripts/taskset.sh
. "$(dirname "$0")/taskset.sh"
fixtures_dir="${1:-$taskset_fixtures}"
snapshots_dir="$root/.applebench/fixtures"

python3 - "$fixtures_dir" <<'PYTHON'
import pathlib
import re
import sys

fixtures_dir = pathlib.Path(sys.argv[1])

# Directories prepare-fixtures.sh keeps. `.solution/` is stripped, so the
# authored fix is free to explain itself.
SHIPPED = ("Sources", "Tests", "UITests", "Design")

# Phrases that only ever appear when the author is talking to the next
# maintainer about the defect, never in code a real app would ship.
LEAK = re.compile(
    r"\b("
    r"BUG"
    r"|the bug\b"
    r"|the fix\b"
    r"|bug #\d"
    r"|broken implementation"
    r"|intentional(ly)?"
    r"|planted"
    r"|on purpose"
    r"|deliberate(ly)?"
    r"|should (instead )?be"
    r")",
    re.IGNORECASE,
)

COMMENT = re.compile(r"(//|/\*|\*|#)")

problems = []

for fixture in sorted(p for p in fixtures_dir.iterdir() if p.is_dir()):
    for shipped in SHIPPED:
        directory = fixture / shipped
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*")):
            if not path.is_file() or path.suffix not in {".swift", ".md"}:
                continue
            for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
                stripped = line.strip()
                is_comment = path.suffix == ".md" or COMMENT.match(stripped)
                if is_comment and LEAK.search(stripped):
                    relative = path.relative_to(fixtures_dir.parent)
                    problems.append(f"{relative}:{number}: {stripped}")

if problems:
    print(f"error: {len(problems)} comment(s) disclose the planted defect to the agent:\n")
    for problem in problems:
        print(f"  {problem}")
    print("\nMove the explanation into the fixture's README.md, which is stripped.")
    sys.exit(1)

print("No fixture discloses its own defect.")
PYTHON

# The second half of the contract: a prepared snapshot for an isolated fixture
# must contain no graded tests and no test target. Only checked when snapshots
# exist, so this stays usable before the first prepare.
if [ "$sources_only" = true ] || [ ! -d "$snapshots_dir" ]; then
    exit 0
fi

python3 - "$root" "$snapshots_dir" <<'PYTHON'
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
snapshots = pathlib.Path(sys.argv[2])
problems = []

for snapshot in sorted(p for p in snapshots.iterdir() if p.is_dir()):
    isolation = subprocess.run(
        [str(root / "Scripts/fixture-isolation.py"), snapshot.name],
        capture_output=True, text=True,
    ).stdout.strip()
    if isolation != "isolate":
        continue

    for suite in ("Tests", "UITests"):
        if (snapshot / suite).exists():
            problems.append(f"{snapshot.name}: ships {suite}/, which is withheld for this fixture")

    for project in snapshot.glob("*.xcodeproj/project.pbxproj"):
        text = project.read_text(errors="replace")
        for kind in ("com.apple.product-type.bundle.unit-test", "com.apple.product-type.bundle.ui-testing"):
            if kind in text:
                problems.append(f"{snapshot.name}: its project still declares a {kind.rsplit('.', 1)[-1]} target")

if problems:
    print(f"error: {len(problems)} snapshot(s) expose how they are graded:\n")
    for problem in problems:
        print(f"  {problem}")
    print("\nRe-run ./Scripts/prepare-fixtures.sh.")
    sys.exit(1)

print("No snapshot exposes its graded tests.")
PYTHON
