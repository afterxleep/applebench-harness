#!/usr/bin/env python3
"""Strip the answer key out of what the site publishes.

A grader's summary is written for the operator reading a run: it names the
test that failed, the source line a mutation targeted and the string it was
replaced with, the exact text a screen was expected to show. On disk that is
right. On the site it is the answer key to a benchmark whose sandbox denies
the same files to the agent, served to anything that reads the page.

The verdict, the counts and the durations survive; the identifiers do not.
Only the site copies are rewritten. Reports/ keeps everything.

Usage:
  redact-published.py <slug>        rewrite site/_data/{reports,benchmarks}/<slug>.*
  redact-published.py --self-test
"""
from __future__ import annotations

import csv
import io
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def strip_parentheticals(text: str, containing: "re.Pattern[str]") -> str:
    """Removes every bracketed span whose contents match, brackets balanced."""
    out = []
    i = 0
    while i < len(text):
        if text[i] == "(":
            depth, j = 0, i
            while j < len(text):
                depth += text[j] == "("
                depth -= text[j] == ")"
                if depth == 0:
                    break
                j += 1
            inner = text[i:j + 1]
            if containing.search(inner):
                # drop the space that led into it too
                while out and out[-1] == " ":
                    out.pop()
                i = j + 1
                continue
        out.append(text[i])
        i += 1
    return "".join(out)


def redact(summary: str) -> str:
    """The summary with everything that would help solve the task removed."""
    text = summary
    # "3 executed, 2 passed, 1 failed, 0 skipped. Failing: Suite/testName()"
    text = re.split(r"[.,;]?\s*(?:—\s*)?[Ff]ailing:\s", text, maxsplit=1)[0]
    # mutation: "... they claim (Sources/X.swift: "old" → "new"), so ..." —
    # the parenthetical nests brackets of its own and may sit mid-sentence,
    # so it is removed by matching its brackets rather than by pattern.
    text = strip_parentheticals(text, containing=re.compile(r"→|Sources/|Tests/"))
    # uiflow / xcodeproj / file: keep the count, drop what was expected
    #   "2 of 2 UI assertion(s) failed in language=en: no element on screen shows "3/4/26"; ..."
    #   "1 of 3 project assertion(s) failed: build setting X is not set"
    #   "appearance difference over a91-reference: 0.00%"
    m = re.match(r"(\d+ of \d+ (?:UI|project|file) assertion\(s\) (?:failed|hold)[^:—]*?)\s*[:.—].*", text, re.S)
    if m:
        text = m.group(1)
    text = re.sub(r"^appearance difference over \S+:", "appearance difference over the region:", text)
    # anything still quoting a literal the screen or a file was expected to hold
    text = re.sub(r"\s+(?:contains|shows|matches|reads)\s+\"[^\"]*\"", " matched the expected text", text)
    # a bare test identifier that survived
    text = re.sub(r"\b[A-Z][A-Za-z0-9]*Tests?/[A-Za-z0-9_]+(?:\(\))?", "a graded test", text)
    return text.strip().rstrip(" —-,;:")


def redact_json(path: pathlib.Path) -> int:
    document = json.loads(path.read_text())
    changed = 0
    for run in document.get("runs", []):
        for grader in run.get("graders", []):
            before = grader.get("summary", "")
            after = redact(before)
            if after != before:
                grader["summary"] = after
                changed += 1
    path.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")
    return changed


def redact_csv(path: pathlib.Path) -> int:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
        fields = handle and rows and list(rows[0].keys())
    if not rows:
        return 0
    changed = 0
    for row in rows:
        cell = row.get("grader_summaries") or row.get("graders_detail") or ""
        key = "grader_summaries" if "grader_summaries" in row else ("graders_detail" if "graders_detail" in row else None)
        if not key:
            # find the column that carries "name:summary | name:summary"
            for candidate, value in row.items():
                if value and " | " in value and ":" in value and re.search(r"\b(build|xctest|xcuitest|file|uiflow|mutation|trajectory|xcodeproj|runtime):", value):
                    key = candidate
                    break
        if not key:
            continue
        parts = row[key].split(" | ")
        new_parts = []
        for part in parts:
            name, _, summary = part.partition(":")
            new_parts.append(f"{name}:{redact(summary)}" if summary else part)
        joined = " | ".join(new_parts)
        if joined != row[key]:
            row[key] = joined
            changed += 1
    with path.open("w", newline="") as handle:
        writer = csv_writer(handle, fields)
        writer.writeheader()
        writer.writerows(rows)
    return changed


def csv_writer(handle, fields):
    return csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")


def self_test() -> int:
    cases = {
        "3 executed, 2 passed, 1 failed, 0 skipped. Failing: DeliveryActivityTests/testStartingWorks()":
            "3 executed, 2 passed, 1 failed, 0 skipped",
        "1 executed, 0 passed, 1 failed, 0 skipped — failing: TariffTests/testRoundingRule()":
            "1 executed, 0 passed, 1 failed, 0 skipped",
        "The tests failed against a deliberately broken app, so they test the behaviour they claim (Sources/CartView.swift: \".accessibilityIdentifier(\\\"cart-item\\\")\" → \".accessibilityIdentifier(\\\"cart-item-mutated\\\")\")":
            "The tests failed against a deliberately broken app, so they test the behaviour they claim",
        "2 of 2 UI assertion(s) failed in language=en locale=en_US: no element on screen shows \"3/4/26\"; no element on screen shows \"11/9/26\"":
            "2 of 2 UI assertion(s) failed in language=en locale=en_US",
        "1 of 3 project assertion(s) failed: build setting SWIFT_ACTIVE_COMPILATION_CONDITIONS is not set":
            "1 of 3 project assertion(s) failed",
        "appearance difference over a91-reference: 0.00%":
            "appearance difference over the region: 0.00%",
        "The tests still passed with the app broken (Sources/BasketView.swift: \"nil\" → \".accessibilityIdentifier(\"$1-mutated\")\"), so they do not assert the behaviour the task asked for":
            "The tests still passed with the app broken, so they do not assert the behaviour the task asked for",
        "1 of 1 project assertion(s) failed — build setting CODE_SIGN_ENTITLEMENTS is not set":
            "1 of 1 project assertion(s) failed",
        "xcodebuild build succeeded for scheme 'CartFixture'":
            "xcodebuild build succeeded for scheme 'CartFixture'",
        "2 file assertion(s) satisfied":
            "2 file assertion(s) satisfied",
    }
    failures = 0
    for given, expected in cases.items():
        got = redact(given)
        if got != expected:
            failures += 1
            print(f"FAIL\n  given:    {given}\n  expected: {expected}\n  got:      {got}")

    csv_buffer = io.StringIO(newline="")
    writer = csv_writer(csv_buffer, ["value"])
    writer.writeheader()
    writer.writerow({"value": "one"})
    if csv_buffer.getvalue() != "value\none\n":
        failures += 1
        print("FAIL\n  published CSV does not use LF line endings")
    print("self-test:", "ok" if failures == 0 else f"{failures} failure(s)")
    return 1 if failures else 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        return self_test()
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    slug = sys.argv[1]
    total = 0
    report = ROOT / f"site/_data/reports/{slug}.json"
    table = ROOT / f"site/_data/benchmarks/{slug}.csv"
    if report.exists():
        total += redact_json(report)
    if table.exists():
        total += redact_csv(table)
    print(f"  redacted {total} grader summar{'y' if total == 1 else 'ies'} in the site copies of {slug}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
