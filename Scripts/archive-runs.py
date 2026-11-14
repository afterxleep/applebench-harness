#!/usr/bin/env python3
"""Copy the readable record of scored runs into the run registry.

The registry is a visible folder in the AppleBench project (`Runs/`), committed
there and never in this repository. A run directory is mostly build output, so
only what lets a result be validated later is copied:

    result.json, metadata.json, adjudication.json   what was run and decided
    events.jsonl                                    the harness event log
    logs/                                           agent and grader logs
    opencode.json                                   agent config, secrets scrubbed
    agent.sb                                        the sandbox profile it ran under
    diff.patch                                      the agent's change, without
                                                    build output and binary blobs

The source run directories are never changed or removed. A run already in the
destination is left as it is.

Usage:
    archive-runs.py [--source DIR] [--dest DIR] [--model ID ...] [--run ID ...]
                    [--reports DIR] [--dry-run]

With no --model/--run it takes every run named in the reports' CSV files.
"""
import argparse
import csv
import json
import os
import pathlib
import re
import shutil
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _paths  # noqa: E402

KEEP_FILES = ["result.json", "metadata.json", "adjudication.json", "events.jsonl", "agent.sb"]
SKIP_DIFF_PATH = re.compile(
    r"(^|/)(build|DerivedData|\.build|Index\.noindex|Pods|node_modules|\.swiftpm|xcuserdata)(/|$)"
    r"|\.(xcresult|a|o|dylib|png|jpg|jpeg|gif|mp4|mov|zip|pdf)(/|$)"
)
SECRET = re.compile(r'("(?:apiKey|api_key|key|token|authorization)"\s*:\s*")[^"]+(")', re.I)
MAX_LOG_BYTES = 25 * 1024 * 1024


TOKEN = re.compile(r"\b(?:sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{30,})")


def scrub(text: str) -> str:
    """Config-style secrets by key name, and anything shaped like a provider key."""
    return TOKEN.sub("REDACTED", SECRET.sub(r"\1REDACTED\2", text))


def filter_diff(src: pathlib.Path, dst: pathlib.Path) -> tuple[int, int]:
    kept = dropped = 0
    out = []
    section = []
    path = None

    def flush():
        nonlocal kept, dropped, section, path
        if not section:
            return
        body = "".join(section)
        binary = "GIT binary patch" in body or "Binary files" in body
        if path and (SKIP_DIFF_PATH.search(path) or binary):
            dropped += 1
        else:
            kept += 1
            out.append(body)
        section = []

    with src.open(errors="replace") as f:
        for line in f:
            if line.startswith("diff --git "):
                flush()
                m = re.match(r"diff --git a/(.+?) b/(.+)$", line.rstrip("\n"))
                path = m.group(2) if m else None
            section.append(line)
    flush()
    note = f"# archive-runs: kept {kept} file section(s), left out {dropped} (build output, binary or media)\n"
    dst.write_text(note + "".join(out))
    return kept, dropped


def archive(run: pathlib.Path, dest_root: pathlib.Path, dry: bool) -> str:
    dest = dest_root / run.name
    if dest.exists():
        return "exists"
    if dry:
        return "would copy"
    dest.mkdir(parents=True)
    for name in KEEP_FILES:
        if (run / name).is_file():
            if name == "events.jsonl":
                (dest / name).write_text(scrub((run / name).read_text(errors="replace")))
            else:
                shutil.copy2(run / name, dest / name)
    if (run / "opencode.json").is_file():
        (dest / "opencode.json").write_text(scrub((run / "opencode.json").read_text(errors="replace")))
    if (run / "logs").is_dir():
        for p in (run / "logs").rglob("*"):
            if p.is_file() and p.stat().st_size <= MAX_LOG_BYTES:
                target = dest / "logs" / p.relative_to(run / "logs")
                target.parent.mkdir(parents=True, exist_ok=True)
                if p.suffix in (".log", ".txt", ".json", ".jsonl"):
                    target.write_text(scrub(p.read_text(errors="replace")))
                else:
                    shutil.copy2(p, target)
    if (run / "diff.patch").is_file():
        filter_diff(run / "diff.patch", dest / "diff.patch")
    return "copied"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=str(pathlib.Path(__file__).resolve().parents[1] / ".applebench/runs"))
    ap.add_argument("--dest", default=str(_paths.runs_dir()))
    ap.add_argument("--reports", default=str(_paths.reports_dir()))
    ap.add_argument("--model", action="append", default=[])
    ap.add_argument("--run", action="append", default=[])
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    source, dest = pathlib.Path(a.source), pathlib.Path(a.dest)
    if source.resolve() == dest.resolve():
        sys.exit("error: source and destination are the same directory")

    wanted = set(a.run)
    if not wanted and not a.model:
        for f in sorted(pathlib.Path(a.reports).glob("*.csv")):
            wanted |= {r["run_id"] for r in csv.DictReader(open(f)) if r.get("run_id")}
    if a.model:
        for run in source.iterdir():
            try:
                model = json.load(open(run / "result.json")).get("agent", {}).get("model")
            except Exception:
                continue
            if model in a.model:
                wanted.add(run.name)

    counts = {}
    for name in sorted(wanted):
        run = source / name
        if not run.is_dir():
            counts["missing"] = counts.get("missing", 0) + 1
            continue
        status = archive(run, dest, a.dry_run)
        counts[status] = counts.get(status, 0) + 1
    print(f"{len(wanted)} run(s) -> {dest}: " + ", ".join(f"{v} {k}" for k, v in sorted(counts.items())))


if __name__ == "__main__":
    main()
