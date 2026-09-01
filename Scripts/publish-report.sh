#!/bin/bash
# Publish a benchmark run: export machine-readable results and copy them
# into the site's data directory so the charts and the report are the same
# numbers.
#
# Usage:
#   ./Scripts/publish-report.sh <slug> [runs-dir]
#
#   slug       Identifier for the published run, e.g. 2026-08-27-minimax
#   runs-dir   Where the run artifacts live (default: .applebench/runs)
#   suite      Which suite was run (default: gold)
#
# Writes:
#   Reports/<slug>.csv          full per-run detail
#   Reports/<slug>.json         aggregate totals plus every run
#   site/_data/benchmarks/<slug>.csv    the site's chart source
#   site/_data/reports/<slug>.json      conditions and totals
#   site/_benchmarks/<slug>.md          the published page
#
# Selection: this exports *every* run found under runs-dir. If a directory
# holds several attempts at the same task, say so in the report — the
# published number depends on which attempt counts, and the reader cannot
# infer that rule from the data.
#
# The write-up in site/_benchmarks/<slug>.md must carry a `suite_revision`
# matching an id in site/_data/suite_revisions.yml. A pass rate is a fraction
# of a particular set of tasks; without the revision a reader cannot tell
# whether a difference is the model or the suite, and the site marks runs on
# a superseded revision so they are not read as comparable.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

slug="${1:-}"
runs_dir="${2:-$root/.applebench/runs}"
suite="${3:-gold}"
if [ -z "$slug" ]; then
    echo "usage: $0 <slug> [runs-dir] [suite]" >&2
    exit 2
fi

binary="$root/.build/release/applebench"
[ -x "$binary" ] || binary="$root/.build/debug/applebench"
if [ ! -x "$binary" ]; then
    echo "Building applebench…"
    swift build -c release
    binary="$root/.build/release/applebench"
fi

mkdir -p "$root/Reports" "$root/site/_data/benchmarks" "$root/site/_data/reports" "$root/site/_benchmarks"

"$binary" results "$runs_dir" --format csv  --output "$root/Reports/$slug.csv"
"$binary" results "$runs_dir" --format json --output "$root/Reports/$slug.json"
cp "$root/Reports/$slug.csv"  "$root/site/_data/benchmarks/$slug.csv"
cp "$root/Reports/$slug.json" "$root/site/_data/reports/$slug.json"

# The page renders itself. Everything on it — the model, the harness and its
# configuration, the host, the pass rate, the charts, the per-task table — is
# read from the exported data, so publishing a run does not depend on anyone
# writing it up correctly by hand. Commentary is optional and goes in the body.
python3 "$root/Scripts/render-benchmark-page.py" "$slug" "$suite"

echo
echo "Published $slug:"
echo "  Reports/$slug.csv"
echo "  Reports/$slug.json"
echo "  site/_data/benchmarks/$slug.csv"
echo "  site/_data/reports/$slug.json"
echo "  site/_benchmarks/$slug.md"
echo
echo "The page is complete as it stands. Add commentary below the front"
echo "matter if there is something the numbers do not say — in particular"
echo "which attempt counts, when a task was re-run."
