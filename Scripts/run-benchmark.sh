#!/bin/bash
# Run a full AppleBench suite and export machine-readable results.
#
# Usage:
#   ./Scripts/run-benchmark.sh [options]
#
# Options:
#   -s, --suite <id>        Suite to run (default: gold)
#   -a, --agent <id>        Agent harness (default: opencode)
#   -m, --model <id>        Model passed to the agent
#   -p, --parallel <n>      Concurrent tasks (default: 1)
#   -o, --out <dir>         Report directory (default: Reports/<suite>-<date>)
#       --runs-dir <dir>    Run artifact root (default: .applebench/runs)
#       --strip-wrapper-clis  Hide wrapper CLIs from the agent's PATH
#       --allow-env <NAME>  Expose an environment variable to the agent
#                           (repeatable). Needed for an API key when
#                           --strip-wrapper-clis is on, because that mode
#                           gives the agent a hermetic HOME and any
#                           credentials stored under the real one go with it.
#
# Everything machine-specific comes from the environment, never from this
# file. To point runs at a self-hosted or proxied endpoint, export
# APPLEBENCH_OPENCODE_PROVIDER with an OpenCode provider block (inline JSON
# or a path to a JSON file) before invoking this script.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# shellcheck source=Scripts/taskset.sh
. "$(dirname "$0")/taskset.sh"

suite="gold"
agent="opencode"
model=""
parallel="1"
out=""
runs_dir="$root/.applebench/runs"
strip_wrappers=""
allow_env=()

while [ $# -gt 0 ]; do
    case "$1" in
        -s|--suite) suite="$2"; shift 2 ;;
        -a|--agent) agent="$2"; shift 2 ;;
        -m|--model) model="$2"; shift 2 ;;
        -p|--parallel) parallel="$2"; shift 2 ;;
        -o|--out) out="$2"; shift 2 ;;
        --runs-dir) runs_dir="$2"; shift 2 ;;
        --strip-wrapper-clis) strip_wrappers="--strip-wrapper-clis"; shift ;;
        --allow-env) allow_env+=(--allow-env "$2"); shift 2 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

stamp="$(date -u +%Y-%m-%d)"
out="${out:-$root/Reports/$suite-$stamp}"
mkdir -p "$out"

binary="$root/.build/release/applebench"
if [ ! -x "$binary" ]; then
    echo "Building applebench (release)…"
    swift build -c release
fi

log="$out/run.log"
if [ -f "$taskset_suites/$suite.yaml" ]; then suite="$taskset_suites/$suite.yaml"; fi

echo "AppleBench · suite=$suite agent=$agent model=${model:-<default>} parallel=$parallel"
echo "  runs:   $runs_dir"
echo "  report: $out"
echo

set +e
"$binary" suite "$suite" \
    --agent "$agent" \
    --tasks-dir "$taskset_tasks" \
    ${model:+--model "$model"} \
    --parallel "$parallel" \
    --runs-dir "$runs_dir" \
    $strip_wrappers \
    ${allow_env[@]+"${allow_env[@]}"} \
    2>&1 | tee "$log"
suite_status=${PIPESTATUS[0]}
set -e

# Export regardless of the suite's exit status: a run with infrastructure
# errors still produced results worth reading, and hiding them would make
# the report look better than the run actually was.
"$binary" results "$runs_dir" --format csv  --output "$out/summary.csv"
"$binary" results "$runs_dir" --format json --output "$out/summary.json"

echo
echo "Wrote:"
echo "  $out/summary.csv"
echo "  $out/summary.json"
echo "  $log"
exit "$suite_status"
