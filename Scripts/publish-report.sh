#!/bin/bash
# Publish a benchmark run: export machine-readable results and copy them
# into the site's data directory so the charts and the report are the same
# numbers.
#
# Usage:
#   ./Scripts/publish-report.sh <slug> [runs-dir] [suite] [options]
#
#   slug       Identifier for the published run, e.g. 2026-08-27-minimax
#   runs-dir   Where the run artifacts live (default: .applebench/runs)
#   suite      Which suite was run (default: gold)
#
# Options:
#   --attempt all|first|latest|best   Which attempt counts when a task was run
#                                     more than once (default: first)
#   --model <id>                      Publish only this model's runs
#
# Writes:
#   Reports/<slug>.csv          full per-run detail
#   Reports/<slug>.json         aggregate totals plus every run
#   site/_data/benchmarks/<slug>.csv    the site's chart source
#   site/_data/reports/<slug>.json      conditions and totals
#   site/_benchmarks/<slug>.md          the published page
#
# Selection: a run directory can hold several attempts at the same task and
# more than one configuration. `--attempt` decides which attempt counts and
# `--model` decides which configuration is published; both are recorded in the
# export, because the headline moves with them and a reader cannot infer either
# from the data. The default is `first`, the strictest reading.
#
# The write-up in site/_benchmarks/<slug>.md must carry a `suite_revision`
# matching an id in site/_data/suite_revisions.yml. A score is a total over a
# particular set of tasks; without the revision a reader cannot tell whether a
# difference is the model or the suite, and the site marks runs on a superseded
# revision so they are not read as comparable.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

slug=""
runs_dir=""
suite=""
attempt="first"
model=""
suite_files=()

while [ $# -gt 0 ]; do
    case "$1" in
        --attempt) attempt="$2"; shift 2 ;;
        --model)   model="$2";   shift 2 ;;
        --suite-file) suite_files+=("$2"); shift 2 ;;
        -*)        echo "unknown option: $1" >&2; exit 2 ;;
        *)
            if   [ -z "$slug" ];     then slug="$1"
            elif [ -z "$runs_dir" ]; then runs_dir="$1"
            elif [ -z "$suite" ];    then suite="$1"
            else echo "unexpected argument: $1" >&2; exit 2
            fi
            shift
            ;;
    esac
done

runs_dir="${runs_dir:-$root/.applebench/runs}"
suite="${suite:-gold}"
if [ -z "$slug" ]; then
    echo "usage: $0 <slug> [runs-dir] [suite] [--attempt RULE] [--model ID]" >&2
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

selection=(--attempt "$attempt")
[ -n "$model" ] && selection+=(--model "$model")
# A published score is a fraction of a stated set of tasks, and a run
# directory holds whatever was run in it. Naming the suite is what keeps the
# public sample tasks — which are never scored — out of a published number.
for file in "${suite_files[@]+"${suite_files[@]}"}"; do selection+=(--suite "$file"); done

"$binary" results "$runs_dir" "${selection[@]}" --format csv  --output "$root/Reports/$slug.csv"
"$binary" results "$runs_dir" "${selection[@]}" --format json --output "$root/Reports/$slug.json"

cp "$root/Reports/$slug.csv"  "$root/site/_data/benchmarks/$slug.csv"
cp "$root/Reports/$slug.json" "$root/site/_data/reports/$slug.json"

# The page renders itself. Everything on it — the model, the harness and its
# configuration, the host, the score, the charts, the per-task table — is
# read from the exported data, so publishing a run does not depend on anyone
# writing it up correctly by hand. Commentary is optional and goes in the body.
python3 "$root/Scripts/render-benchmark-page.py" "$slug" "$suite"

echo
echo "Published $slug (attempt: $attempt${model:+, model: $model}):"
echo "  Reports/$slug.csv"
echo "  Reports/$slug.json"
echo "  site/_data/benchmarks/$slug.csv"
echo "  site/_data/reports/$slug.json"
echo "  site/_benchmarks/$slug.md"
echo
echo "The page is complete as it stands. Add commentary below the front"
echo "matter if there is something the numbers do not say — in particular"
echo "why this attempt rule, and what was excluded."
