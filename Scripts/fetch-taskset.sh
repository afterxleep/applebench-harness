#!/bin/bash
# Puts the task set on disk at a stated revision, and prints where.
#
# Usage (sourced or executed):
#   ./Scripts/fetch-taskset.sh <repo-url> [ref] [dir]
#
# The clone lives inside the harness, never the other way round: nothing the
# harness generates is written back to the task set.
#
# The ref matters. A task set is fetched by URL alone only while everything
# scored lives on the default branch, and the moment a suite is prepared on a
# branch a run machine fetching by URL scores the wrong set — silently, because
# the tasks it wanted simply are not there. Naming the revision is what makes a
# run reproducible: the resolved commit is printed so it can be recorded.
set -euo pipefail

repo="${1:-}"
ref="${2:-}"
dir="${3:-}"

if [ -z "$repo" ]; then
    echo "usage: $0 <repo-url> [ref] [dir]" >&2
    exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
dir="${dir:-$root/.applebench/taskset}"

if [ -d "$dir/.git" ]; then
    echo "Updating task set in ${dir}…" >&2
    git -C "$dir" fetch --quiet --all --prune
else
    echo "Cloning task set from ${repo}…" >&2
    mkdir -p "$(dirname "$dir")"
    if ! git clone --quiet "$repo" "$dir"; then
        echo "error: could not clone $repo (private task sets need your git credentials)." >&2
        exit 1
    fi
fi

if [ -n "$ref" ]; then
    if ! git -C "$dir" checkout --quiet "$ref" 2>/dev/null \
        && ! git -C "$dir" checkout --quiet -B "$ref" "origin/$ref" 2>/dev/null; then
        echo "error: $repo has no ref '$ref'." >&2
        exit 1
    fi
fi

# Fast-forward only, and only when the checkout is on a branch: a task set that
# has diverged locally is a different set, and silently merging it would score
# tasks the published number does not name. A detached tag or sha has nothing
# to fast-forward and is left alone.
if branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD)"; then
    if git -C "$dir" rev-parse --quiet --verify "origin/$branch" >/dev/null; then
        if ! git -C "$dir" merge --ff-only --quiet "origin/$branch"; then
            echo "error: $dir could not be fast-forwarded. Resolve it or delete the directory." >&2
            exit 1
        fi
    fi
fi

commit="$(git -C "$dir" rev-parse --short HEAD)"
echo "Task set at ${ref:-$(git -C "$dir" rev-parse --abbrev-ref HEAD)} (${commit})" >&2
echo "$dir"
