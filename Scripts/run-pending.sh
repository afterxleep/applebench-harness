#!/bin/bash
# Runs only the tasks a model still owes: the ones it has never been scored on,
# and the ones that have changed since it was.
#
# Usage:
#   ./Scripts/run-pending.sh --model <id> --api-key <key> [options]
#
# Options:
#   --report <slug>   Report to compare against (default: newest in Reports/)
#   --suite <id>      Suite to consider (default: every gold* suite)
#   --new-only        Only tasks never scored; skip changed ones
#   --changed-only    Only tasks that changed; skip new ones
#   --list            Print what would run and stop
#   ...plus anything else, forwarded to run-benchmark.sh
#
# There is deliberately no git in here. A task is its prompt, its graders and
# its fixture, so "has this changed" is a question about content, and content
# survives branches, merges, rebases and renames. Comparing against a branch
# name stops meaning anything the moment that branch is merged.
#
# The comparison is against a published report, because that is the thing that
# actually knows what a model has been scored on.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# shellcheck source=Scripts/taskset.sh
. "$(dirname "$0")/taskset.sh"

model=""
report=""
suite=""
mode="both"
list_only="no"
forward=()

while [ $# -gt 0 ]; do
    case "$1" in
        --model|-m)     model="$2"; forward+=(--model "$2"); shift 2 ;;
        --report)       report="$2"; shift 2 ;;
        --suite|-s)     suite="$2"; shift 2 ;;
        --new-only)     mode="new"; shift ;;
        --changed-only) mode="changed"; shift ;;
        --list)         list_only="yes"; shift ;;
        *)              forward+=("$1"); shift ;;
    esac
done

if [ -z "$model" ]; then
    echo "error: --model is required" >&2
    exit 2
fi

if [ -z "$report" ]; then
    report="$(ls -t "$root"/Reports/*.json 2>/dev/null | head -1 || true)"
    [ -n "$report" ] && report="$(basename "$report" .json)"
fi

pending="$(APPLEBENCH_TASKSET="$taskset_root" python3 "$root/Scripts/pending-tasks.py" \
    --model "$model" \
    ${report:+--report "$root/Reports/$report.json"} \
    ${suite:+--suite "$taskset_suites/$suite.yaml"} \
    --mode "$mode")"

if [ -z "$pending" ]; then
    echo "Nothing pending: $model is up to date with every task in the set."
    exit 0
fi

count="$(echo "$pending" | wc -w | tr -d ' ')"
echo "Pending for $model ($count task(s), against ${report:-no report}):"
echo "  $pending"
echo

if [ "$list_only" = "yes" ]; then
    exit 0
fi

# Fixtures are rebuilt first: a changed task usually means a changed fixture,
# and running against a stale snapshot would score the wrong thing.
"$root/Scripts/prepare-fixtures.sh" >/dev/null

# shellcheck disable=SC2086
exec "$root/Scripts/run-benchmark.sh" "${forward[@]}" --tasks $pending
