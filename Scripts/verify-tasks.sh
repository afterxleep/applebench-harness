#!/bin/bash
# Proves the fail-then-pass contract for the named tasks, one at a time.
#
# This is the narrow, resumable counterpart to verify-fixtures.sh: it takes an
# explicit task list, bounds every run, and cleans up after itself. A run that
# is interrupted leaves its dedicated `AppleBench-*` simulator booted, and a
# stray booted simulator makes the next `xcodebuild test` hang indefinitely
# against the run's own device — so leftovers are removed after every task
# rather than at the end.
#
# Usage:
#   ./Scripts/verify-tasks.sh runtime-002 build-002
#   TIMEOUT=600 ./Scripts/verify-tasks.sh visual-002
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# shellcheck source=Scripts/taskset.sh
. "$(dirname "$0")/taskset.sh"

binary=".build/debug/applebench"
timeout_seconds="${TIMEOUT:-420}"

if ! swift build --product applebench >/dev/null; then
    echo "error: swift build failed" >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    echo "usage: $0 <task-id> [task-id ...]" >&2
    exit 1
fi

# Two runs at once means two booted simulators, and `xcodebuild test` hangs
# indefinitely against its own device when another one is up. Every task in
# the overlap then times out, which reads as a suite full of broken fixtures
# and is nothing of the sort.
#
# A check for a running process is not enough on its own: two sweeps that
# start while the machine is idle both see nothing and both proceed. The lock
# is a directory because mkdir is atomic.
lock="${TMPDIR:-/tmp}/applebench-verify.lock"
if ! mkdir "$lock" 2>/dev/null; then
    holder="$(cat "$lock/pid" 2>/dev/null || echo unknown)"
    if [ "$holder" != unknown ] && ! kill -0 "$holder" 2>/dev/null; then
        # The holder is gone — an interrupted sweep. Take it over.
        rm -rf "$lock"
        mkdir "$lock" 2>/dev/null || { echo "error: could not take the verification lock" >&2; exit 1; }
    else
        echo "error: another verification sweep is in flight (pid $holder)." >&2
        echo "Verification runs must be serial; wait for it or stop it first." >&2
        exit 1
    fi
fi
echo $$ > "$lock/pid"

# Removes the per-run simulators the benchmark creates. Named devices belonging
# to the user are matched by neither pattern and are left alone.
cleanup_leftovers() {
    xcrun simctl list devices 2>/dev/null \
        | grep -oE "AppleBench-[^ ]+ \([0-9A-F-]{36}\)" \
        | grep -oE "[0-9A-F-]{36}" \
        | while read -r udid; do
            xcrun simctl shutdown "$udid" >/dev/null 2>&1
            xcrun simctl delete "$udid" >/dev/null 2>&1
        done
}

# Interrupting a sweep used to leave its simulator booted: the trap released
# the lock and nothing reaped the device. A stray booted simulator makes the
# next `xcodebuild test` hang against its own destination.
#
# The run has to die *before* the reap. Reaping first deletes a device the
# still-running child immediately recreates, which is exactly what happened:
# the lock was released, the sweep exited, and the simulator was left booted
# anyway.
on_exit() {
    if [ -n "${run_pid:-}" ] && kill -0 "$run_pid" 2>/dev/null; then
        kill -TERM "$run_pid" 2>/dev/null
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$run_pid" 2>/dev/null || break
            sleep 1
        done
        kill -KILL "$run_pid" 2>/dev/null
    fi
    cleanup_leftovers
    rm -rf "$lock"
}
trap on_exit EXIT INT TERM

# A run reports PASS/FAIL on its own line. Anything else is a run that could
# not execute credibly: the harness prints those as `error: ...`, which the
# verdict grep does not match, and an unmatched verdict used to be reported as
# TIMEOUT — sending anyone debugging it after a wall-clock problem that was
# never there.
verdict_of() {
    local output
    local log
    log="$(mktemp)"
    # `-k` matters: xcodebuild can wedge against a simulator and ignore the
    # SIGTERM `timeout` sends at the deadline, and a plain `timeout` then waits
    # on it forever. One such run sat for two hours past its own limit. The
    # follow-up SIGKILL is what actually bounds the sweep.
    timeout -k 60 "$timeout_seconds" "$binary" run "$1" --agent "$2" --tasks-dir "$taskset_tasks" >"$log" 2>&1 &
    run_pid=$!
    wait "$run_pid"
    local status=$?
    run_pid=""
    output="$(cat "$log")"
    rm -f "$log"
    local verdict
    verdict="$(printf '%s\n' "$output" | grep -E "^(PASS|FAIL)" | head -1 | cut -d' ' -f1)"
    if [ -n "$verdict" ]; then
        printf '%s' "$verdict"
    elif [ "$status" -eq 124 ]; then
        printf 'TIMEOUT'
    else
        printf 'ERROR'
        printf '%s\n' "$output" | grep -E "^error:" | head -1 >&2
    fi
}

# Each run keeps its own derived data as evidence. Across a full sweep that is
# a couple of hundred copies of a build directory, which fills the disk and
# then every remaining task times out — a full suite of false verdicts with no
# obvious cause. The verdict is already recorded by the time this runs, and
# the logs and result bundles stay.
discard_derived_data() {
    find "$root/.applebench/runs" -maxdepth 2 -name DerivedData -type d -mmin +1 \
        -exec rm -rf {} + 2>/dev/null || true
}

failures=0

printf "%-20s %-8s %-8s %s\n" "task" "fake" "solution" "verdict"
printf -- "----------------------------------------------------\n"

for task in "$@"; do
    fake="$(verdict_of "$task" fake)"
    cleanup_leftovers
    solution="$(verdict_of "$task" solution)"
    cleanup_leftovers
    discard_derived_data

    if [ "$fake" = "FAIL" ] && [ "$solution" = "PASS" ]; then
        verdict="ok"
    else
        verdict="BROKEN"
        failures=$((failures + 1))
    fi

    printf "%-20s %-8s %-8s %s\n" "$task" "${fake:-TIMEOUT}" "${solution:-TIMEOUT}" "$verdict"
done

if [ "$failures" -gt 0 ]; then
    echo
    echo "$failures task(s) do not hold the fail-then-pass contract" >&2
    exit 1
fi
