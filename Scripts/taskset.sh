# Locates the task set a command should operate on.
#
# The harness and the tasks live in different repositories: the harness is
# public and the scoring tasks are not. A task set is any directory laid out
# like the one bundled here:
#
#   <taskset>/Examples/Tasks/*.yaml
#   <taskset>/Examples/Suites/*.yaml
#   <taskset>/Fixtures/<Name>/
#
# Point at one with APPLEBENCH_TASKSET. With nothing set, the commands use the
# task set bundled with the harness, so a fresh clone runs without arguments.
#
# Sourced, not executed.

taskset_root="${APPLEBENCH_TASKSET:-$root}"
if [ ! -d "$taskset_root" ]; then
    echo "error: APPLEBENCH_TASKSET is not a directory: $taskset_root" >&2
    exit 1
fi
taskset_root="$(cd "$taskset_root" && pwd)"

taskset_tasks="$taskset_root/Examples/Tasks"
taskset_suites="$taskset_root/Examples/Suites"
taskset_fixtures="$taskset_root/Fixtures"

for required in "$taskset_tasks" "$taskset_fixtures"; do
    if [ ! -d "$required" ]; then
        echo "error: $taskset_root does not look like a task set (missing ${required#$taskset_root/})" >&2
        exit 1
    fi
done
