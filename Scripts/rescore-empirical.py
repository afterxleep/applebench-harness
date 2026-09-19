#!/usr/bin/env python3
"""Rescore every published report under empirical-v1.

Task weights come from the observed pass rates across the complete published
model runs for the current suite (one CSV per model under
site/_data/benchmarks/), not from the authored difficulty:

    weight = min(2000, floor(100 * modelCount / passingModelCount + 0.5))
    (a task no model passes earns the 2000-point cap)

The script writes the shared weights file, then recomputes each report's
headline score, per-category scores, per-configuration scores, and the
per-task face_value/points columns in both the Reports/ and site/ copies.
Raw pass rates and verdicts are left exactly as they were.

Run it whenever a new complete model is published: adding a complete model
can change every task weight, so every complete model is rescored without
being rerun.

Usage:
  rescore-empirical.py            rescore from site/_data/benchmarks/*.csv
  rescore-empirical.py --self-test
"""
from __future__ import annotations

import csv
import io
import json
import math
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BENCHMARKS = ROOT / "site/_data/benchmarks"
REPORTS = ROOT / "site/_data/reports"
ARCHIVE = ROOT / "Reports"
WEIGHTS_PATH = ROOT / "site/_data/empirical_weights.json"

SPECIFICATION = "empirical-v1"
BASE_WEIGHT = 100
MAX_WEIGHT = 2000


def task_weight(model_count: int, passing_count: int) -> int | None:
    if model_count <= 0 or passing_count < 0 or passing_count > model_count:
        return None
    if passing_count == 0:
        return MAX_WEIGHT
    return min(MAX_WEIGHT, math.floor(BASE_WEIGHT * model_count / passing_count + 0.5))


def compute_weights(tables: dict[str, list[dict]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    passing: dict[str, int] = {}
    for rows in tables.values():
        for row in rows:
            task = row["task"]
            counts[task] = counts.get(task, 0) + 1
            if row["passed"] == "true":
                passing[task] = passing.get(task, 0) + 1
    weights = {}
    for task, count in counts.items():
        weight = task_weight(count, passing.get(task, 0))
        if weight is not None:
            weights[task] = weight
    return weights


def score(rows: list[dict], weights: dict[str, int]) -> dict:
    points = available = scored = unscored = 0
    for row in rows:
        weight = weights.get(row["task"])
        if weight is None:
            unscored += 1
            continue
        scored += 1
        available += weight
        if row["passed"] == "true":
            points += weight
    return {
        "specification": SPECIFICATION,
        "points": points,
        "available": available,
        "fraction_of_available": points / available if available else 0,
        "percentage": (points / available * 100) if available else 0,
        "scored_runs": scored,
        "unscored_runs": unscored,
    }


def rewrite_csv(path: pathlib.Path, weights: dict[str, int]) -> None:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        fields = reader.fieldnames or []
    for row in rows:
        weight = weights.get(row["task"])
        row["face_value"] = str(weight) if weight is not None else ""
        row["points"] = str(weight) if weight is not None and row["passed"] == "true" else ""
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def rewrite_report(path: pathlib.Path, rows: list[dict], weights: dict[str, int]) -> None:
    document = json.loads(path.read_text())
    document["score"] = score(rows, weights)
    document["task_weights"] = dict(sorted(weights.items()))
    for category in document.get("categories", []):
        member = [row for row in rows if row.get("category") == category["category"]]
        category["score"] = score(member, weights)
    for configuration in document.get("configurations", []):
        member = [
            row for row in rows
            if row.get("model") == configuration.get("model")
        ]
        configuration["score"] = score(member, weights)
    path.write_text(json.dumps(document, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


def self_test() -> int:
    failures = 0

    def check(given, expected, label):
        nonlocal failures
        if given != expected:
            failures += 1
            print(f"FAIL {label}: expected {expected}, got {given}")

    check(task_weight(5, 5), 100, "5/5")
    check(task_weight(5, 4), 125, "4/5")
    check(task_weight(5, 3), 167, "3/5")
    check(task_weight(5, 2), 250, "2/5")
    check(task_weight(5, 1), 500, "1/5")
    check(task_weight(5, 0), 2000, "0/5 caps")
    check(task_weight(25, 1), 2000, "cap applies")
    check(task_weight(0, 0), None, "no models is unscored")

    weights = compute_weights({
        "m1": [{"task": "a", "passed": "true"}, {"task": "b", "passed": "true"}],
        "m2": [{"task": "a", "passed": "true"}],
        "m3": [{"task": "a", "passed": "false"}],
    })
    check(weights, {"a": 150, "b": 100}, "weights")

    with tempfile.TemporaryDirectory() as directory:
        report = pathlib.Path(directory) / "report.json"
        report.write_text(json.dumps({
            "score": {"specification": "complexity-v1"},
            "categories": [{"category": "ops", "score": {}}],
            "configurations": [{"model": "m", "score": {}}],
            "runs": [],
        }))
        rows = [{"task": "a", "category": "ops", "model": "m", "passed": "true"}]
        rewrite_report(report, rows, {"a": 150})
        published = json.loads(report.read_text())
        check(published["score"]["specification"], SPECIFICATION, "spec")
        check(published["score"]["points"], 150, "points")
        check(published["categories"][0]["score"]["available"], 150, "category available")
        check(published["configurations"][0]["score"]["points"], 150, "configuration points")
        check(published["task_weights"], {"a": 150}, "task_weights recorded")

        table = pathlib.Path(directory) / "table.csv"
        table.write_text("task,passed,face_value,points\na,true,7,7\n")
        rewrite_csv(table, {"a": 150})
        published_rows = list(csv.DictReader(io.StringIO(table.read_text())))
        check(published_rows[0]["face_value"], "150", "csv face value")
        check(published_rows[0]["points"], "150", "csv points")

    print("self-test:", "ok" if failures == 0 else f"{failures} failure(s)")
    return 1 if failures else 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        return self_test()
    if len(sys.argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2

    slugs = sorted(path.stem for path in BENCHMARKS.glob("*.csv"))
    if not slugs:
        print("no published benchmark CSVs found", file=sys.stderr)
        return 1
    tables = {}
    for slug in slugs:
        with (BENCHMARKS / f"{slug}.csv").open(newline="") as handle:
            tables[slug] = list(csv.DictReader(handle))

    weights = compute_weights(tables)
    WEIGHTS_PATH.write_text(json.dumps(weights, indent=2, sort_keys=True) + "\n")
    # A static copy the site can serve: Jekyll renders _data for templates but
    # does not publish the file itself.
    (ROOT / "site/empirical_weights.json").write_text(
        json.dumps(weights, indent=2, sort_keys=True) + "\n"
    )
    print(f"weights for {len(weights)} tasks from {len(slugs)} complete runs -> {WEIGHTS_PATH.relative_to(ROOT)}")

    for slug in slugs:
        rewrite_csv(BENCHMARKS / f"{slug}.csv", weights)
        rows = tables[slug]
        if (REPORTS / f"{slug}.json").exists():
            rewrite_report(REPORTS / f"{slug}.json", rows, weights)
        if (ARCHIVE / f"{slug}.csv").exists():
            rewrite_csv(ARCHIVE / f"{slug}.csv", weights)
        if (ARCHIVE / f"{slug}.json").exists():
            rewrite_report(ARCHIVE / f"{slug}.json", rows, weights)
        result = score(rows, weights)
        passed = sum(row["passed"] == "true" for row in rows)
        print(f"  {slug}: {passed}/{len(rows)} passed, score {result['points']}/{result['available']} = {result['percentage']:.2f}%")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
