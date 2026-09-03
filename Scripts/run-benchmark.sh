#!/bin/bash
# Run a full AppleBench suite and export machine-readable results.
#
# Usage:
#   ./Scripts/run-benchmark.sh [options]
#
# Options:
#   -s, --suite <id>        Suite to run (default: gold)
#       --pending           Run only what this model still owes: tasks it has
#                           never been scored on, plus tasks that have changed
#                           since it was. Needs --model. Nothing is marked by
#                           hand — a task is its prompt, its graders and its
#                           fixture, so what changed is decided by hashing those
#                           and comparing against what the model's last report
#                           recorded. Exits without running when nothing is due.
#       --new-only          --pending, restricted to tasks never scored
#       --changed-only      --pending, restricted to tasks that changed
#   -a, --agent <id>        Agent harness (default: opencode)
#   -m, --model <id>        Model passed to the agent
#   -e, --effort <level>    Reasoning effort, forwarded to OpenCode as the
#                           model variant. Valid levels are per-provider
#                           (minimal, low, medium, high, max), so the value
#                           is passed through rather than validated. Recorded
#                           on the run, since effort changes the number.
#       --max-tokens <n>    Stop a task once it has spent this many tokens.
#                           The wall clock is a poor proxy for spend: a model
#                           can burn a budget in two minutes or idle for
#                           twenty. Tightens each task's own limit, never
#                           loosens it.
#       --timeout-cap <s>   Ceiling on every task's wall-clock timeout, in
#                           seconds. Defaults to 1200, twenty minutes: far
#                           more than any measured task needs, and enough to
#                           bound one that has stopped making progress.
#                           Tightening only: a task that asks for less keeps
#                           what its author gave it.
#       --agent-arg <arg>   Extra argument forwarded verbatim to the agent CLI
#                           (repeatable). The escape hatch for anything the
#                           flags above do not cover.
#   -p, --parallel <n>      Concurrent tasks (default: 1)
#   -o, --out <dir>         Report directory (default: Reports/<suite>-<date>)
#       --runs-dir <dir>    Run artifact root (default: .applebench/runs)
#       --strip-wrapper-clis  Hide wrapper CLIs from the agent's PATH
#       --task-set-ref <r>  Branch, tag or sha to score. Without it the default
#                           branch is used, which silently scores the wrong set
#                           whenever a suite is prepared on a branch. Also read
#                           from APPLEBENCH_TASKSET_REF.
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
pending_mode=""
agent="opencode"
model=""
effort=""
max_tokens=""
timeout_cap=""
agent_arg=()
parallel="1"
out=""
runs_dir="$root/.applebench/runs"
strip_wrappers=""
allow_env=()
api_key=""
api_key_file=""
api_key_variable="OPENROUTER_API_KEY"
task_set_repo="${APPLEBENCH_TASKSET_REPO:-}"
task_set_ref="${APPLEBENCH_TASKSET_REF:-}"
task_set_dir=""
vm=""
vm_allow=()
vm_user=""
vm_password=""

while [ $# -gt 0 ]; do
    case "$1" in
        -s|--suite) suite="$2"; shift 2 ;;
        --pending)      pending_mode="both"; shift ;;
        --new-only)     pending_mode="new"; shift ;;
        --changed-only) pending_mode="changed"; shift ;;
        -a|--agent) agent="$2"; shift 2 ;;
        -m|--model) model="$2"; shift 2 ;;
        -e|--effort) effort="$2"; shift 2 ;;
        --max-tokens) max_tokens="$2"; shift 2 ;;
        --timeout-cap) timeout_cap="$2"; shift 2 ;;
        --agent-arg) agent_arg+=(--agent-arg "$2"); shift 2 ;;
        -p|--parallel) parallel="$2"; shift 2 ;;
        -o|--out) out="$2"; shift 2 ;;
        --runs-dir) runs_dir="$2"; shift 2 ;;
        --strip-wrapper-clis) strip_wrappers="--strip-wrapper-clis"; shift ;;
        --allow-env) allow_env+=(--allow-env "$2"); shift 2 ;;
        --task-set-repo) task_set_repo="$2"; shift 2 ;;
        --task-set-ref)  task_set_ref="$2";  shift 2 ;;
        --task-set-dir) task_set_dir="$2"; shift 2 ;;
        --api-key) api_key="$2"; shift 2 ;;
        --api-key-file) api_key_file="$2"; shift 2 ;;
        --vm) vm="$2"; shift 2 ;;
        --vm-allow) vm_allow+=(--vm-allow "$2"); shift 2 ;;
        --vm-user) vm_user="$2"; shift 2 ;;
        --vm-password) vm_password="$2"; shift 2 ;;
        -h|--help) sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
    APPLEBENCH_TASKSET="$("$root/Scripts/fetch-taskset.sh" "$task_set_repo" "$task_set_ref" "${task_set_dir:-}")"
    export APPLEBENCH_TASKSET
elif [ -n "$task_set_dir" ]; then
    echo "error: --task-set-dir needs --task-set-repo (or APPLEBENCH_TASKSET_REPO); to use a task set already on disk, set APPLEBENCH_TASKSET." >&2
    exit 2
fi

# shellcheck source=Scripts/taskset.sh
. "$(dirname "$0")/taskset.sh"


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

# Fixtures are prepared before every run, not only when the task set was just
# cloned. A suite run against unprepared fixtures does not fail once: it fails
# per task, as a wall of "repository does not exist" errors that read like a
# broken task set rather than a missing setup step.
#
# prepare-fixtures.sh is idempotent, so the cost of doing this every time is a
# few seconds against never being able to run the wrong thing.
echo "Preparing fixtures…"
if ! "$(dirname "$0")/prepare-fixtures.sh" >"$out/prepare.log" 2>&1; then
    echo "error: preparing fixtures failed. See $out/prepare.log" >&2
    exit 1
fi

binary="$root/.build/release/applebench"
if [ ! -x "$binary" ]; then
    echo "Building applebench (release)…"
    swift build -c release
fi

log="$out/run.log"
if [ -f "$taskset_suites/$suite.yaml" ]; then suite="$taskset_suites/$suite.yaml"; fi

# Pending mode narrows the suite to the tasks this model actually owes. The
# selection is written out as a suite of its own rather than filtered inside
# the runner, so the run records exactly which tasks it was given.
if [ -n "$pending_mode" ]; then
    if [ -z "$model" ]; then
        echo "error: --pending needs --model: what is outstanding is per model." >&2
        exit 2
    fi
    pending="$(APPLEBENCH_TASKSET="$taskset_root" python3 "$root/Scripts/pending-tasks.py" \
        --model "$model" --reports-dir "$root/Reports" \
        --suite "$suite" --mode "$pending_mode")"
    if [ -z "$pending" ]; then
        echo "Nothing pending: $model is up to date with every task in $(basename "$suite" .yaml)."
        exit 0
    fi
    count="$(echo "$pending" | wc -w | tr -d " ")"
    echo "Pending for $model ($count task(s)):"
    echo "  $pending"
    echo
    pending_suite="$out/pending-suite.yaml"
    {
        echo "id: pending"
        echo "name: \"Pending for $model\""
        echo "tasks:"
        for task in $pending; do echo "  - $task"; done
    } > "$pending_suite"
    suite="$pending_suite"
fi

echo "AppleBench · suite=$suite agent=$agent model=${model:-<default>} effort=${effort:-<default>} parallel=$parallel"
echo "  caps:   tokens=${max_tokens:-unlimited} timeout=${timeout_cap:-1200}s"
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
    ${effort:+--effort "$effort"} \
    ${max_tokens:+--max-tokens "$max_tokens"} \
    ${timeout_cap:+--timeout-cap "$timeout_cap"} \
    ${agent_arg[@]+"${agent_arg[@]}"} \
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


# A run is only a useful record of *currency* if it also says what each task
# was at the time. Recording it here rather than at publish time means an
# unpublished run still counts as covered, so `--pending` does not re-run work
# that has already been done.
APPLEBENCH_TASKSET="$taskset_root" python3 "$root/Scripts/task-fingerprints.py" > "$out/fingerprints.json"
python3 - "$out/summary.json" "$out/fingerprints.json" <<'PYTHON'
import json, sys
with open(sys.argv[1]) as handle:
    document = json.load(handle)
with open(sys.argv[2]) as handle:
    document["task_fingerprints"] = json.load(handle)
with open(sys.argv[1], "w") as handle:
    json.dump(document, handle, indent=2, sort_keys=True)
PYTHON
rm -f "$out/fingerprints.json"
echo
echo "Wrote:"
echo "  $out/summary.csv"
echo "  $out/summary.json"
echo "  $log"
exit "$suite_status"
