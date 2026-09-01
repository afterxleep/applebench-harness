#!/bin/bash
# Proves the fail-then-pass contract for benchmark tasks.
#
# A task is only a meaningful benchmark item if it FAILs for an agent that
# changes nothing and PASSes once the known fix is applied. For each task this
# runs:
#
#   applebench run <id> --agent fake      -> must FAIL
#   applebench run <id> --agent solution  -> must PASS
#
# Usage:
#   ./Scripts/verify-fixtures.sh                 # every task in Examples/Tasks
#   ./Scripts/verify-fixtures.sh build-001 ...   # only the named tasks
#
# Exits non-zero on any deviation, and on any run that could not execute
# credibly (exit code 2 from `applebench run`).
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# shellcheck source=Scripts/taskset.sh
. "$(dirname "$0")/taskset.sh"

tasks_dir="$taskset_tasks"
if [ "$#" -gt 0 ]; then
    tasks=("$@")
else
    tasks=()
    for file in "$tasks_dir"/*.yaml; do
        [ -e "$file" ] || continue
        tasks+=("$(basename "$file" .yaml)")
    done
fi

if [ "${#tasks[@]}" -eq 0 ]; then
    echo "error: no tasks to verify" >&2
    exit 1
fi

echo "Building applebench..."
if ! swift build --product applebench >/dev/null; then
    echo "error: swift build failed" >&2
    exit 1
fi

# One engine for both entry points. verify-tasks.sh bounds each run, deletes
# the per-run simulator afterwards, and refuses to start alongside another
# run — an interrupted run leaves its simulator booted, and a stray booted
# simulator makes the next `xcodebuild test` hang against its own device.
exec "$root/Scripts/verify-tasks.sh" "${tasks[@]}"
