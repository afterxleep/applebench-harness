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
#       --task-set-repo <u> Git URL of the task set to score. Cloned on first
#                           use and fast-forwarded after, then prepared. Also
#                           read from APPLEBENCH_TASKSET_REPO, so a scoring
#                           run is one command on a fresh machine.
#       --task-set-dir <d>  Where that clone lives (default:
#                           .applebench/taskset)
#       --api-key <key>     OpenRouter key to run with. Exposed to the agent
#                           as OPENROUTER_API_KEY; no need to export it or
#                           pass --allow-env yourself.
#       --api-key-file <p>  Read that key from a file instead. Prefer this:
#                           an argument is visible in `ps` to every process
#                           on the machine and lands in your shell history.
#       --allow-env <NAME>  Expose an environment variable to the agent
#                           (repeatable). Needed for an API key when
#                           --strip-wrapper-clis is on, because that mode
#                           gives the agent a hermetic HOME and any
#                           credentials stored under the real one go with it.
#       --vm <image>        Run the agent inside a Tart VM instead of on this
#                           host. Egress is denied at the network layer, the
#                           guest sees only the workspace and the harness's
#                           own OpenCode config, and grading still happens on
#                           the host after the VM is stopped.
#       --vm-allow <CIDR>   Range the VM may reach (repeatable). Omit for a
#                           fully offline guest; a hosted model needs its
#                           provider's range.
#       --vm-user <name>    SSH user for the VM image (default: admin)
#       --vm-password <pw>  SSH password for the VM image (default: admin)
#
# Without --vm the agent runs on this host, and "no network" means its
# toolset: webfetch is denied and plugins are off, but nothing stops it
# shelling out to curl. Only --vm enforces it.
#
# Everything machine-specific comes from the environment, never from this
# file. To point runs at a self-hosted or proxied endpoint, export
# APPLEBENCH_OPENCODE_PROVIDER with an OpenCode provider block (inline JSON
# or a path to a JSON file) before invoking this script.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

suite="gold"
agent="opencode"
model=""
parallel="1"
out=""
runs_dir="$root/.applebench/runs"
strip_wrappers=""
allow_env=()
api_key=""
api_key_file=""
api_key_variable="OPENROUTER_API_KEY"
task_set_repo="${APPLEBENCH_TASKSET_REPO:-}"
task_set_dir=""
vm=""
vm_allow=()
vm_user=""
vm_password=""

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
        --task-set-repo) task_set_repo="$2"; shift 2 ;;
        --task-set-dir) task_set_dir="$2"; shift 2 ;;
        --api-key) api_key="$2"; shift 2 ;;
        --api-key-file) api_key_file="$2"; shift 2 ;;
        --vm) vm="$2"; shift 2 ;;
        --vm-allow) vm_allow+=(--vm-allow "$2"); shift 2 ;;
        --vm-user) vm_user="$2"; shift 2 ;;
        --vm-password) vm_password="$2"; shift 2 ;;
        -h|--help) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

# Materialise the task set before anything reads it. The tasks live in their
# own repository, so a scoring run on a fresh machine would otherwise be clone,
# export, prepare, run, with three chances to point at the wrong directory.
#
# The clone lives inside the harness, never the other way round: nothing the
# harness generates is written back to the task set.
if [ -n "$task_set_repo" ]; then
    task_set_dir="${task_set_dir:-$root/.applebench/taskset}"
    if [ -d "$task_set_dir/.git" ]; then
        echo "Updating task set in ${task_set_dir}…"
        # Fast-forward only: a task set that has diverged locally is a
        # different set, and silently merging it would score the wrong tasks.
        if ! git -C "$task_set_dir" pull --ff-only --quiet; then
            echo "error: $task_set_dir could not be fast-forwarded. Resolve it or delete the directory." >&2
            exit 1
        fi
    else
        echo "Cloning task set from ${task_set_repo}…"
        mkdir -p "$(dirname "$task_set_dir")"
        if ! git clone --quiet "$task_set_repo" "$task_set_dir"; then
            echo "error: could not clone $task_set_repo (private task sets need your git credentials)." >&2
            exit 1
        fi
    fi
    APPLEBENCH_TASKSET="$(cd "$task_set_dir" && pwd)"
    export APPLEBENCH_TASKSET
elif [ -n "$task_set_dir" ]; then
    echo "error: --task-set-dir needs --task-set-repo (or APPLEBENCH_TASKSET_REPO); to use a task set already on disk, set APPLEBENCH_TASKSET." >&2
    exit 2
fi

# shellcheck source=Scripts/taskset.sh
. "$(dirname "$0")/taskset.sh"

if [ -n "$task_set_repo" ]; then
    echo "Preparing fixtures…"
    "$(dirname "$0")/prepare-fixtures.sh" >/dev/null
fi

# A key given on the command line or in a file is put into the environment here
# and allowlisted automatically, so the caller does not have to remember to do
# both. Getting only one of the two right is the failure that looks like a bad
# model: the agent launches, cannot authenticate, and every task fails.
if [ -n "$api_key" ] && [ -n "$api_key_file" ]; then
    echo "error: pass --api-key or --api-key-file, not both." >&2
    exit 2
fi
if [ -n "$api_key_file" ]; then
    if [ ! -r "$api_key_file" ]; then
        echo "error: --api-key-file cannot be read: $api_key_file" >&2
        exit 2
    fi
    api_key="$(tr -d '[:space:]' < "$api_key_file")"
    if [ -z "$api_key" ]; then
        echo "error: --api-key-file is empty: $api_key_file" >&2
        exit 2
    fi
fi
if [ -n "$api_key" ]; then
    export "$api_key_variable=$api_key"
    # Do not allowlist it twice if the caller also passed --allow-env for it.
    case " ${allow_env[*]-} " in
        *" $api_key_variable "*) ;;
        *) allow_env+=(--allow-env "$api_key_variable") ;;
    esac
fi

# --vm-allow without --vm reads as "isolated except for this range" and is in
# fact a completely unisolated run, so refuse it rather than run the wrong thing.
if [ -z "$vm" ] && { [ "${#vm_allow[@]}" -gt 0 ] || [ -n "$vm_user" ] || [ -n "$vm_password" ]; }; then
    echo "error: --vm-allow/--vm-user/--vm-password need --vm; without it the agent runs on this host with no egress restriction at all." >&2
    exit 2
fi

# Runtime tasks crash the app on purpose, and macOS puts a "quit unexpectedly"
# dialog on screen for each one unless CrashReporter is told not to. Over a
# suite that is one modal dialog per crashing task, on top of whatever else the
# operator is doing. Warn rather than write the preference: it is a global user
# setting and a benchmark script has no business changing one silently.
crash_dialog_type="$(defaults read com.apple.CrashReporter DialogType 2>/dev/null || echo unset)"
case "$crash_dialog_type" in
    none|server) ;;
    *)
        echo "note: macOS will show a crash dialog for every task whose app crashes, and"
        echo "      several tasks crash by design. Silence them with:"
        echo "        defaults write com.apple.CrashReporter DialogType none"
        echo "      Undo later with: defaults delete com.apple.CrashReporter DialogType"
        echo
        ;;
esac

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
if [ -n "$vm" ]; then
    if [ "${#vm_allow[@]}" -gt 0 ]; then
        echo "  vm:     $vm, egress denied except ${vm_allow[*]//--vm-allow/}"
    else
        echo "  vm:     $vm, all egress denied"
    fi
else
    echo "  vm:     none, agent runs on this host and its egress is not restricted"
fi
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
    ${vm:+--vm "$vm"} \
    ${vm_allow[@]+"${vm_allow[@]}"} \
    ${vm_user:+--vm-user "$vm_user"} \
    ${vm_password:+--vm-password "$vm_password"} \
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
