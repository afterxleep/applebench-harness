#!/usr/bin/env python3
"""Expands an archived `summary.json` back into a directory of `result.json` files.

A published export is produced by `applebench results`, which reads the
`result.json` written next to each run's workspace. Those workspaces are large
and are not kept forever; the aggregate `summary.json` is, and its `runs[]`
entries are the same documents verbatim. This writes them back out so an
archived run can be re-exported through the real code path rather than by
hand-editing the export it produced last time.

It invents nothing. Every field written comes from the summary, and no run is
dropped, renamed, or merged. Artifact paths inside a restored run point at
files that no longer exist locally, which is the honest state of an archive.

Usage:
    import-run-summary.py <summary.json> <destination-directory>
"""
import json
import pathlib
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
    destination = pathlib.Path(sys.argv[2])

    runs = summary.get("runs", [])
    if not runs:
        print(f"error: no runs in {sys.argv[1]}", file=sys.stderr)
        return 1

    seen: set[str] = set()
    for run in runs:
        run_id = run.get("run_id")
        if not run_id:
            print("error: a run has no run_id; refusing to guess one", file=sys.stderr)
            return 1
        if run_id in seen:
            print(f"error: duplicate run_id {run_id}", file=sys.stderr)
            return 1
        seen.add(run_id)

        directory = destination / run_id
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "result.json").write_text(
            json.dumps(run, indent=2, sort_keys=True) + "\n"
        )

    print(f"Restored {len(runs)} run(s) to {destination}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
