#!/usr/bin/env python3
"""Re-keys published reports by model instead of by date.

A date-keyed report is a snapshot: `gold-2026-09-02` says what a model scored
that day and stops being true the moment anything is re-run. What a reader
wants, and what `--pending` needs, is the *current* score for a model — one
report per model, updated in place, with the dates kept inside it where they
belong.

Renames, in the harness and on the site together, so nothing points at a file
that no longer exists:

    Reports/<slug>.json                 →  Reports/<model>.json
    Reports/<slug>.csv                  →  Reports/<model>.csv
    site/_data/reports/<slug>.json      →  site/_data/reports/<model>.json
    site/_data/benchmarks/<slug>.csv    →  site/_data/benchmarks/<model>.csv
    site/_benchmarks/<slug>.md          →  site/_benchmarks/<model>.md

and rewrites the page's `data:` key to match.

A report holding more than one model is left alone: splitting it is a
publishing decision, not a rename, and guessing would lose data.

Usage:
    migrate-reports-by-model.py [--dry-run]
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def slug(model: str) -> str:
    """`minimax/MiniMax-M2.7` → `minimax-m2-7`.

    The provider prefix is dropped: within one benchmark the model names are
    what people say out loud, and `minimax-minimax-m3` reads like a mistake.
    """
    name = model.rsplit("/", 1)[-1].lower()
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", name)).strip("-")


def move(source: pathlib.Path, destination: pathlib.Path, dry_run: bool) -> None:
    if not source.exists() or source == destination:
        return
    print(f"  {source.relative_to(ROOT)} → {destination.relative_to(ROOT)}")
    if dry_run:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    # `git mv` where the file is tracked, so history follows the rename.
    tracked = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", str(source)],
        capture_output=True,
    ).returncode == 0
    if tracked:
        subprocess.run(["git", "-C", str(ROOT), "mv", "-f", str(source), str(destination)], check=True)
    else:
        source.replace(destination)


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    reports = ROOT / "Reports"
    migrated = 0

    for path in sorted(reports.glob("*.json")):
        try:
            document = json.loads(path.read_text())
        except (ValueError, OSError):
            continue
        models = sorted({r.get("agent", {}).get("model") for r in document.get("runs", [])} - {None})
        if len(models) != 1:
            print(f"skipping {path.name}: {len(models)} models, splitting it is a publishing decision")
            continue

        old, new = path.stem, slug(models[0])
        if old == new:
            continue
        print(f"{old} → {new}  ({models[0]})")
        move(path, reports / f"{new}.json", dry_run)
        move(reports / f"{old}.csv", reports / f"{new}.csv", dry_run)
        move(ROOT / f"site/_data/reports/{old}.json", ROOT / f"site/_data/reports/{new}.json", dry_run)
        move(ROOT / f"site/_data/benchmarks/{old}.csv", ROOT / f"site/_data/benchmarks/{new}.csv", dry_run)

        page = ROOT / f"site/_benchmarks/{old}.md"
        if page.exists():
            text = page.read_text()
            move(page, ROOT / f"site/_benchmarks/{new}.md", dry_run)
            if not dry_run:
                target = ROOT / f"site/_benchmarks/{new}.md"
                target.write_text(re.sub(rf"^data: {re.escape(old)}$", f"data: {new}", text, flags=re.MULTILINE))
        migrated += 1

    print(f"\n{migrated} report(s) re-keyed by model." if migrated else "\nNothing to migrate.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
