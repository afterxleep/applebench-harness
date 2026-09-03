#!/bin/bash
# Puts the task set on disk at a stated revision, and prints where.
#
# Usage (sourced or executed):
#   ./Scripts/fetch-taskset.sh <repo-url> [dir]
#
# The clone lives inside the harness, never the other way round: nothing the
# harness generates is written back to the task set.
#
# Everything scored lives on the default branch, so there is nothing to name.
# The resolved commit is printed so a run can record what it scored.
set -euo pipefail

repo="${1:-}"
dir="${2:-}"

if [ -z "$repo" ]; then
    echo "usage: $0 <repo-url> [dir]" >&2
    exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
dir="${dir:-$root/.applebench/taskset}"

if [ -d "$dir/.git" ]; then
    echo "Updating task set in ${dir}..." >&2
    git -C "$dir" fetch --quiet --all --prune
else
    echo "Cloning task set from ${repo}..." >&2
    mkdir -p "$(dirname "$dir")"
    if ! git clone --quiet "$repo" "$dir"; then
        echo "error: could not clone $repo (private task sets need your git credentials)." >&2
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
echo "Task set at $(git -C "$dir" rev-parse --abbrev-ref HEAD) (${commit})" >&2
echo "$dir"
