#!/usr/bin/env python3
"""Regenerate docs/TASKS.md from Examples/Tasks/*.yaml."""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1]
tasks_dir = root / "Examples/Tasks"
out = root / "docs/TASKS.md"

CATEGORIES = [
    "build", "tests", "runtime", "visual", "interaction",
    "project", "frameworks", "ops",
]


def scalar(text, key):
    match = re.search(rf"^{key}:[ \t]*(.+?)[ \t]*$", text, re.MULTILINE)
    return match.group(1).strip().strip('"\'') if match else None


def block(text, key):
    match = re.search(rf"^{key}:[ \t]*\|[ \t]*\n((?:^[ \t]+.*\n?)*)", text, re.MULTILINE)
    if not match:
        match = re.search(rf'^{key}:[ \t]*"([\s\S]*?)"\s*$', text, re.MULTILINE)
        if match:
            return bytes(match.group(1), "utf-8").decode("unicode_escape")
        return ""
    lines = []
    for line in match.group(1).splitlines():
        lines.append(re.sub(r"^  ", "", line))
    return "\n".join(lines).strip()


def fixture_name(text):
    for line in text.splitlines():
        if "fixtures/" in line:
            return line.split("fixtures/")[-1].strip()
    return "(none)"


def grader_summary(text):
    types = re.findall(r"^[ \t]*- type: (\w+)", text, re.MULTILINE)
    return "; ".join(f"`{t}`" for t in types) if types else "(none)"


tasks = []
for path in sorted(tasks_dir.glob("*.yaml")):
    text = path.read_text()
    tasks.append({
        "id": path.stem,
        "title": scalar(text, "title") or path.stem,
        "category": scalar(text, "category") or "uncategorized",
        "difficulty": int(scalar(text, "difficulty") or 0),
        "tags": scalar(text, "tags") or "",
        "fixture": fixture_name(text),
        "prompt": block(text, "prompt") or "(see YAML)",
        "graders": grader_summary(text),
        "text": text,
    })

gold = {
    line.strip()[2:].strip()
    for line in (root / "Examples/Suites/gold.yaml").read_text().splitlines()
    if line.strip().startswith("- ")
}
dev = {
    line.strip()[2:].strip()
    for line in (root / "Examples/Suites/dev.yaml").read_text().splitlines()
    if line.strip().startswith("- ")
}

lines = [
    "# AppleBench task reference",
    "",
    "Every task in the benchmark, what it asks, and what the grader checks.",
    "Tasks are grouped by category, sorted by id within each category.",
    "",
    "Conventions:",
    "- **Fixture** is the repo the agent starts in",
    "- **Prompt** is what the agent sees",
    "- **Graders** is the list of graders applied to the agent's final workspace",
    "- **Set** is `gold` (private scoring) or `dev` (public, not scored)",
    "",
    "All tasks assume the agent has only the standard Apple toolchain:",
    "`xcodebuild`, `xcrun simctl`, `xcrun devicectl`, `swift`, `xcresulttool`.",
    "No Homebrew installs, no internet, no third-party CLI.",
    "",
    f"**Total: {len(tasks)} tasks** — {len(gold)} gold, {len(dev)} public-dev — across {len(CATEGORIES)} categories.",
    "",
    "Language-level Swift and concurrency are out of scope (covered by other",
    "benches). This set is skewed toward Apple frameworks and operational work.",
    "",
]

by_cat = {c: [] for c in CATEGORIES}
for task in tasks:
    by_cat.setdefault(task["category"], []).append(task)

for category in CATEGORIES:
    group = by_cat.get(category, [])
    lines.append(f"## {category.title()} ({len(group)} tasks)")
    lines.append("")
    for task in sorted(group, key=lambda t: t["id"]):
        membership = "dev" if task["id"] in dev else "gold"
        lines.append(f"### {task['id']} — {task['title']}")
        lines.append("")
        lines.append(f"- **Difficulty:** {task['difficulty']}/10")
        lines.append(f"- **Fixture:** `{task['fixture']}`")
        lines.append(f"- **Set:** {membership}")
        lines.append(f"- **Graders:** {task['graders']}")
        lines.append("")
        lines.append("**Prompt:**")
        lines.append("")
        lines.append(task["prompt"])
        lines.append("")
        lines.append("---")
        lines.append("")

out.write_text("\n".join(lines).rstrip() + "\n")
print(f"Wrote {out} ({len(tasks)} tasks)")
