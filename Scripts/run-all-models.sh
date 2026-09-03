#!/bin/bash
# Run everything outstanding, for every model already published, one after another.
#
# Usage:
#   ./Scripts/run-all-models.sh [options]
#
# Options are forwarded verbatim to run-benchmark.sh, so anything that script
# takes works here. --changed and --model are supplied per model and must not
# be passed.
#
#   --dry-run          Print what each model owes and stop.
#   --model <id>       Add a model that has no published report yet
#                      (repeatable). Without one, the set is every model any
#                      report has scored.
#
# Sequential on purpose. Two benchmarks can share this machine safely, but they
# share one Xcode, one CoreSimulator and one disk, and a task that times out
# because the other run was mid-build is a scoring result that says nothing
# about the model. The wall clock is not what this measures.
#
# Every model runs even if an earlier one failed: a provider outage on the
# third model should not cost the two that already worked, and the exit code
# reports how many fell over.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

dry_run=""
extra=()
models=()

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run="yes"; shift ;;
        --model) models+=("$2"); shift 2 ;;
        --changed|--changed-only)
            echo "note: --changed is implied for every model; ignoring it." >&2
            shift ;;
        *) extra+=("$1"); shift ;;
    esac
done

# The published reports are the record of who has been scored, which is the
# same list --changed compares against.
while IFS= read -r model; do
    [ -n "$model" ] || continue
    case " ${models[*]-} " in *" $model "*) continue ;; esac
    models+=("$model")
done < <(python3 - <<'PY'
import json, pathlib
found = set()
for path in sorted(pathlib.Path("Reports").glob("*.json")):
    try:
        document = json.loads(path.read_text())
    except (ValueError, OSError):
        continue
    for run in document.get("runs", []):
        model = run.get("agent", {}).get("model")
        if model:
            found.add(model)
print("\n".join(sorted(found)))
PY
)

if [ "${#models[@]}" -eq 0 ]; then
    echo "error: no models to run. Publish a report first, or name one with --model." >&2
    exit 2
fi

echo "Models to run (${#models[@]}):"
for model in "${models[@]}"; do echo "  $model"; done
echo

if [ -n "$dry_run" ]; then
    suite_file="$root/.applebench/taskset/Examples/Suites/gold.yaml"
    [ -f "$suite_file" ] || suite_file="${APPLEBENCH_TASKSET:-$root}/Examples/Suites/gold.yaml"
    for model in "${models[@]}"; do
        pending="$(python3 "$root/Scripts/pending-tasks.py" --model "$model" --suite "$suite_file" 2>/dev/null)"
        count="$(echo "$pending" | wc -w | tr -d ' ')"
        echo "$model owes $count task(s)"
        [ "$count" -gt 0 ] && echo "  $pending"
    done
    exit 0
fi

started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
failed=()
skipped=()

for model in "${models[@]}"; do
    echo
    echo "============================================================"
    echo "  $model  ($(date +%H:%M:%S))"
    echo "============================================================"
    # run-benchmark.sh exits 0 having done nothing when a model is up to date,
    # so "nothing pending" and "ran and passed" both look like success. The log
    # is what tells them apart, and only the failure needs distinguishing.
    if "$root/Scripts/run-benchmark.sh" --changed --model "$model" ${extra[@]+"${extra[@]}"}; then
        :
    else
        status=$?
        echo "note: $model exited $status; continuing with the rest." >&2
        failed+=("$model")
    fi
done

echo
echo "============================================================"
echo "  Started $started, finished $(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ "${#failed[@]}" -eq 0 ]; then
    echo "  All ${#models[@]} model(s) completed."
else
    echo "  ${#failed[@]} of ${#models[@]} model(s) failed: ${failed[*]}"
fi
echo "============================================================"

[ "${#failed[@]}" -eq 0 ] || exit 1
