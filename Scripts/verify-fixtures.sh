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
#   ./Scripts/verify-fixtures.sh [options] [task-id ...]
#
# Options:
#   --task-set-repo <url>      Task set to verify. Fetched into
#                              .applebench/taskset. Defaults to
#                              APPLEBENCH_TASKSET_REPO, then to the clone
#                              already there, then to the bundled samples.
#   --modified-since <instant> Only tasks whose `modified:` is later than this,
#                              e.g. 2026-09-15T09:00:00+02:00.
#   --timeout <seconds>        Per-run ceiling (default: 1800).
#
# Everything a verification needs is set up here: the task set is fetched, its
# fixtures prepared, and the withheld tests made available to grading. Runs go
# to a temporary directory that is removed afterwards, so the repository is
# left as it was.
#
# Exits non-zero on any deviation, and on any run that could not execute
# credibly.
set -uo pipefail

# Tasks in <tasks-dir> whose `modified:` instant is later than <instant>, one
# id per line. Undated tasks are left out: nothing says when they changed.
tasks_modified_since() {
    python3 - "$1" "$2" <<'PY'
import datetime, pathlib, re, sys
def instant(text):
    text = text.strip().strip('"').strip("'").replace("Z", "+00:00")
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        text += "T23:59:59+00:00"
    value = datetime.datetime.fromisoformat(text)
    return value if value.tzinfo else value.replace(tzinfo=datetime.timezone.utc)
since = instant(sys.argv[2])
for path in sorted(pathlib.Path(sys.argv[1]).glob("*.yaml")):
    found = re.search(r"^modified:\s*(\S+)", path.read_text(), re.MULTILINE)
    if found and instant(found.group(1)) > since:
        print(path.stem)
PY
}

main() {
    root="$(cd "$(dirname "$0")/.." && pwd)"
    cd "$root"

    local repo="${APPLEBENCH_TASKSET_REPO:-}"
    local since=""
    local timeout_seconds="1800"
    local requested=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --task-set-repo) repo="$2"; shift 2 ;;
            --modified-since) since="$2"; shift 2 ;;
            --timeout) timeout_seconds="$2"; shift 2 ;;
            -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
            *) requested+=("$1"); shift ;;
        esac
    done

    if [ -z "${APPLEBENCH_TASKSET:-}" ]; then
        if [ -z "$repo" ] && [ -d "$root/.applebench/taskset/.git" ]; then
            repo="$(git -C "$root/.applebench/taskset" remote get-url origin)"
        fi
        if [ -n "$repo" ]; then
            APPLEBENCH_TASKSET="$("$root/Scripts/fetch-taskset.sh" "$repo")" || exit 1
            export APPLEBENCH_TASKSET
        fi
    fi

    # shellcheck source=Scripts/taskset.sh
    . "$root/Scripts/taskset.sh"

    echo "Preparing fixtures..."
    if ! "$root/Scripts/prepare-fixtures.sh" >/dev/null; then
        echo "error: preparing fixtures failed; run ./Scripts/prepare-fixtures.sh to see why" >&2
        exit 1
    fi

    # The withheld tests are fetched from the task set at the commit being
    # verified, exactly as a scoring run grades. Without these a solution run
    # has no hidden tests to pass and every isolated task reads as broken.
    if git -C "$taskset_root" rev-parse --git-dir >/dev/null 2>&1; then
        APPLEBENCH_VERIFICATION_REPOSITORY="$(git -C "$taskset_root" remote get-url origin 2>/dev/null || echo "$taskset_root")"
        APPLEBENCH_VERIFICATION_REVISION="$(git -C "$taskset_root" rev-parse HEAD)"
        APPLEBENCH_VERIFICATION_MANIFEST="$root/.applebench/verification-fixtures.txt"
        export APPLEBENCH_VERIFICATION_REPOSITORY APPLEBENCH_VERIFICATION_REVISION APPLEBENCH_VERIFICATION_MANIFEST
    fi

    local tasks=()
    if [ "${#requested[@]}" -gt 0 ]; then
        tasks=("${requested[@]}")
    elif [ -n "$since" ]; then
        while IFS= read -r task; do
            [ -n "$task" ] && tasks+=("$task")
        done < <(tasks_modified_since "$taskset_tasks" "$since")
    else
        for file in "$taskset_tasks"/*.yaml; do
            [ -e "$file" ] || continue
            tasks+=("$(basename "$file" .yaml)")
        done
    fi

    if [ "${#tasks[@]}" -eq 0 ]; then
        echo "error: no tasks to verify" >&2
        exit 1
    fi
    echo "Verifying ${#tasks[@]} task(s) from $taskset_root"

    local runs_dir
    runs_dir="$(mktemp -d "${TMPDIR:-/tmp}/applebench-verify-runs.XXXXXX")"

    # One engine for both entry points. verify-tasks.sh bounds each run, deletes
    # its own simulators afterwards, and refuses to start alongside another
    # verification — an interrupted run leaves its simulator booted, and a stray
    # booted simulator makes the next `xcodebuild test` hang against its own
    # device.
    TIMEOUT="$timeout_seconds" RUNS_DIR="$runs_dir" "$root/Scripts/verify-tasks.sh" "${tasks[@]}"
    local status=$?
    # The runs are the only evidence of why a task is broken, so they are kept
    # when anything failed and removed when everything held.
    if [ "$status" -eq 0 ]; then
        rm -rf "$runs_dir"
    else
        echo "Run logs for the failing tasks are in $runs_dir" >&2
    fi
    return "$status"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
