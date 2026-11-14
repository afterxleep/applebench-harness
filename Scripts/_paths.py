"""Where the harness keeps its data. It keeps none of its own.

Reports and run artifacts live in the task set's checkout (a visible folder in
the AppleBench project, committed there), never in this repository:

    $APPLEBENCH_REPORTS_DIR   else  $APPLEBENCH_TASKSET/Reports
    $APPLEBENCH_RUNS_DIR      else  $APPLEBENCH_TASKSET/Runs

With neither set, the old in-repo locations (Reports/, .applebench/runs) are
used so an unconfigured checkout still works, but nothing there is committed.
"""
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def _env(name):
    value = os.environ.get(name)
    return pathlib.Path(value).expanduser() if value else None


def taskset():
    return _env("APPLEBENCH_TASKSET")


def reports_dir():
    explicit = _env("APPLEBENCH_REPORTS_DIR")
    if explicit:
        return explicit
    return taskset() / "Reports" if taskset() else ROOT / "Reports"


def runs_dir():
    explicit = _env("APPLEBENCH_RUNS_DIR")
    if explicit:
        return explicit
    return taskset() / "Runs" if taskset() else ROOT / ".applebench" / "runs"
