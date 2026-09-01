#!/bin/bash
# Regenerates Fixtures/<name>/solution.patch from the fixture's authored fix.
#
# A fixture describes its fix as an overlay directory, .solution/, holding the
# corrected version of every file that changes — plus, for fixtures whose defect
# lives in the project configuration, a project.solution.yml holding the
# corrected XcodeGen spec.
#
# The patch is produced by generating the fixture twice — once broken, once
# fixed — through exactly the pipeline prepare-fixtures.sh uses (XcodeGen, then
# stripping the authoring files) and diffing the results. That is what makes
# the patch apply cleanly to the snapshot an agent actually receives, including
# for defects planted in project.yml where the real change lands in generated
# .xcodeproj files.
#
# Usage:
#   ./Scripts/make-solutions.sh                 # every fixture with a .solution/
#   ./Scripts/make-solutions.sh BuildFixture    # only the named fixtures
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=Scripts/taskset.sh
. "$(dirname "$0")/taskset.sh"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen is required (brew install xcodegen)" >&2
    exit 1
fi

python3 - "$taskset_root" "$@" <<'PYTHON'
import pathlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
requested = sys.argv[2:]

fixtures_dir = root / "Fixtures"
names = requested or sorted(p.name for p in fixtures_dir.iterdir() if p.is_dir())

# Files that exist only to author the fixture and never reach an agent. Must
# match the strip list in prepare-fixtures.sh.
AUTHORING = ["project.yml", "project.solution.yml", "README.md", "solution.patch"]


def materialize(source: pathlib.Path, destination: pathlib.Path, fixed: bool) -> None:
    """Builds one side of the diff exactly as prepare-fixtures.sh would."""
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(".solution"))

    if fixed:
        overlay = source / ".solution"
        if overlay.is_dir():
            for path in sorted(overlay.rglob("*")):
                relative = path.relative_to(overlay)
                target = destination / relative
                if path.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                # A zero-byte file in the overlay means "delete this file".
                elif path.stat().st_size == 0 and target.exists():
                    target.unlink()
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(path, target)
        solution_spec = destination / "project.solution.yml"
        if solution_spec.exists():
            shutil.copy2(solution_spec, destination / "project.yml")

    if (destination / "project.yml").exists():
        subprocess.run(
            ["xcodegen", "generate", "--quiet"],
            cwd=destination, check=True,
        )
    for name in AUTHORING:
        (destination / name).unlink(missing_ok=True)


def rewrite(patch: str) -> str:
    """Strips the broken/ and fixed/ path components from the diff headers.

    A file present on only one side is named after that side on *both* halves
    of the header — `a/fixed/x b/fixed/x` for an addition. Stripping only the
    expected side leaves a mismatched header. A text hunk survives that,
    because `git apply` can still read the name off `+++`; a binary hunk has
    no `---`/`+++` at all and fails with "diff header lacks filename
    information". So both prefixes come off both sides.
    """
    lines = []
    for line in patch.splitlines():
        if line.startswith("diff --git "):
            line = (line.replace(" a/broken/", " a/").replace(" a/fixed/", " a/")
                        .replace(" b/broken/", " b/").replace(" b/fixed/", " b/"))
        elif line.startswith("--- "):
            line = line.replace("--- a/broken/", "--- a/").replace("--- a/fixed/", "--- a/")
        elif line.startswith("+++ "):
            line = line.replace("+++ b/fixed/", "+++ b/").replace("+++ b/broken/", "+++ b/")
        elif line.startswith("rename from broken/"):
            line = "rename from " + line[len("rename from broken/"):]
        elif line.startswith("rename to fixed/"):
            line = "rename to " + line[len("rename to fixed/"):]
        lines.append(line)
    return "\n".join(lines) + "\n"


generated, skipped = [], []
for name in names:
    fixture = fixtures_dir / name
    if not fixture.is_dir():
        sys.exit(f"error: no such fixture: Fixtures/{name}")
    if not (fixture / ".solution").is_dir() and not (fixture / "project.solution.yml").exists():
        skipped.append(name)
        continue

    with tempfile.TemporaryDirectory() as scratch:
        scratch = pathlib.Path(scratch)
        materialize(fixture, scratch / "broken", fixed=False)
        materialize(fixture, scratch / "fixed", fixed=True)
        result = subprocess.run(
            ["git", "diff", "--no-index", "--binary", "--", "broken", "fixed"],
            cwd=scratch, capture_output=True, text=True,
        )
        # git diff --no-index exits 1 when the trees differ, which is the
        # expected case; anything else is a real failure.
        if result.returncode not in (0, 1):
            sys.exit(f"error: git diff failed for {name}: {result.stderr}")
        if not result.stdout.strip():
            sys.exit(f"error: {name}'s .solution/ changes nothing — the fixture cannot be proven solvable")

        (fixture / "solution.patch").write_text(rewrite(result.stdout))
        changed = sum(1 for line in result.stdout.splitlines() if line.startswith("diff --git "))
        generated.append((name, changed))

for name, changed in generated:
    print(f"  {name}: solution.patch regenerated ({changed} file(s))")
if skipped:
    print(f"  skipped (no .solution/ overlay): {', '.join(skipped)}")
if not generated:
    print("Nothing to generate.")
PYTHON
