#!/usr/bin/env python3
"""Writes the site page for a published run, entirely from its exported data.

A run's numbers and conditions are already recorded — the model, the harness
and how it was configured, the host, the per-task results. Restating them by
hand is how a published page comes to disagree with the data it links to, so
the page is generated and the layout reads the rest at build time.

Only commentary is left to a person, and the page is complete without it. An
existing body is preserved: re-publishing a run refreshes the facts in the
front matter and leaves what anyone wrote below it alone.

Usage:
    render-benchmark-page.py <slug> [suite]
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def current_suite_revision() -> str:
    """The revision marked current in the site's revision list."""
    revisions = ROOT / "site/_data/suite_revisions.yml"
    if not revisions.exists():
        return ""
    identifier = ""
    for line in revisions.read_text().splitlines():
        found = re.match(r'^-\s*id:\s*"?([^"\s]+)"?', line)
        if found:
            identifier = found.group(1)
        if re.match(r"^\s*current:\s*true", line):
            return identifier
    return ""


def date_from(slug: str, report: dict) -> str:
    if found := re.match(r"(\d{4}-\d{2}-\d{2})", slug):
        return found.group(1)
    for run in report.get("runs", []):
        if found := re.match(r"(\d{4}-\d{2}-\d{2})", run.get("run_id", "")):
            return found.group(1)
    return ""


def describe(report: dict) -> tuple[str, str]:
    """The model and harness a run used, as one line each.

    A run directory can hold more than one configuration — a model reached two
    ways, or a re-run through a different route. All of them are named rather
    than silently reporting the first.
    """
    configurations = report.get("configurations", [])
    models = sorted({c.get("model", "") for c in configurations if c.get("model")})

    # Pair each agent with the version it ran at, rather than listing agents
    # and versions separately and leaving the reader to guess which is which.
    harnesses = set()
    for run in report.get("runs", []):
        agent = run.get("agent", {})
        name = agent.get("agent", "")
        if not name:
            continue
        version = agent.get("version", "")
        harnesses.add(f"{name} {version}".strip())
    return ", ".join(models), ", ".join(sorted(harnesses))


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    slug = sys.argv[1]
    suite = sys.argv[2] if len(sys.argv) > 2 else "gold"

    report_path = ROOT / f"Reports/{slug}.json"
    if not report_path.exists():
        print(f"error: no export at {report_path}", file=sys.stderr)
        return 1
    report = json.loads(report_path.read_text())

    total = report.get("total", 0)
    passed = report.get("passed", 0)
    rate = report.get("completion_rate", 0) * 100
    model, harness = describe(report)

    page = ROOT / f"site/_benchmarks/{slug}.md"
    body = ""
    if page.exists():
        existing = page.read_text()
        if existing.startswith("---"):
            body = existing.split("---", 2)[2].lstrip("\n")

    title = f"{model or harness or slug}, {suite} suite, {rate:.1f}%"
    front = [
        "---",
        f'title: "{title}"',
        f"date: {date_from(slug, report)}",
        f"suite: {suite}",
        f'suite_revision: "{current_suite_revision()}"',
        f"data: {slug}",
        f'model: "{model}"',
        f'harness: "{harness}"',
        f"tasks: {total}",
        f"passed: {passed}",
        "description: >-",
        f"  AppleBench results for {model or harness or slug} on the {suite} suite:",
        f"  {passed} of {total} tasks completed to a verified result, with",
        "  per-category pass rates, cost against wall-clock time, and every task.",
        "---",
        "",
    ]
    page.write_text("\n".join(front) + body)
    print(f"  wrote site/_benchmarks/{slug}.md ({passed}/{total}, {rate:.1f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
