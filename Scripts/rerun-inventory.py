#!/usr/bin/env python3
"""What each model still owes, from the task set's history and the scored runs.

Compares every model's latest run of every task against the task as it was when
that run started (task YAML and agent-visible fixture files, via git), and sorts
each (model, task) pair into one decision:

  NEVER-RUN      no scored run exists.
  RERUN          agent-visible change (prompt, starter, environment, limits,
                 repository) with an old FAIL or timeout, or a removed/changed
                 requirement; or a grader change on an old FAIL.
  REVIEW         old PASS, but the prompt gained text or a grader changed:
                 keep only with artifact proof (the audit's rule). Needs a human
                 or a regrade, not a blind rerun.
  KEEP           nothing that can change a verdict (date, tags, title,
                 category, difficulty, solution files).

It also lists tasks whose last change has no newer verification log, because a
task change is not done until fail-then-pass printed ok.

Usage:
    rerun-inventory.py [--taskset DIR] [--reports DIR] [--model SLUG ...]
                       [--out DIR] [--suites-dir DIR]

Writes <out>/inventory.md and inventory.json, and one rerun suite per model
(RERUN + NEVER-RUN tasks) into --suites-dir. Nothing is run.
"""
from __future__ import annotations
import argparse, csv, datetime as dt, glob, json, os, pathlib, re, subprocess, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _paths  # noqa: E402

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("error: PyYAML is required (pip install pyyaml)")

ROOT = pathlib.Path(__file__).resolve().parents[1]
VISIBLE_KEYS = ("environment", "repository", "timeout", "limits", "setup", "withheld")
INERT_KEYS = {"modified", "title", "category", "difficulty", "tags", "id"}


def sh(taskset, *args):
    return subprocess.run(["git", "-C", str(taskset), *args], capture_output=True, text=True).stdout


def load(text):
    try:
        return yaml.safe_load(text) or {}
    except yaml.YAMLError:
        return {}


def norm(x):
    # The runtime named in a prompt was retargeted (iOS 26.5 to 27.2) with the
    # task's environment block; that is not a wording change.
    return re.sub(r"\s+", " ", re.sub(r"iOS 26\.5", "iOS 27.2", str(x or ""))).strip()


def run_instant(run_id):
    """Run ids carry UTC (events.jsonl stamps the same instant with a trailing Z)."""
    m = re.match(r"(\d{4})-(\d\d)-(\d\d)T(\d\d)(\d\d)(\d\d)", run_id)
    return dt.datetime(*map(int, m.groups()), tzinfo=dt.timezone.utc).timestamp() if m else None


def fixture_of(task):
    m = re.search(r"fixtures/(\w+)", (task.get("repository") or {}).get("url", ""))
    return m.group(1) if m else None


def prompt_kind(old, new):
    o, n = norm(old), norm(new)
    if o == n:
        return None
    # Added text only: every old sentence still present in the new prompt.
    sentences = [s for s in re.split(r"(?<=[.!?])\s+", o) if s]
    return "prompt-added" if all(s in n for s in sentences) else "prompt-changed"


def runtime_only(old, new):
    """True when two environment blocks differ only in the simulator runtime."""
    def strip(env):
        env = json.loads(json.dumps(env or {}))
        if isinstance(env.get("simulator"), dict):
            env["simulator"].pop("runtime", None)
        return env
    return strip(old) == strip(new)


def classify(taskset, name, new, ts, cache):
    commit = cache.setdefault(ts, sh(taskset, "rev-list", "-1", f"--before={int(ts)}", "HEAD").strip())
    if not commit:
        return ["no-baseline"]
    old_text = sh(taskset, "show", f"{commit}:Examples/Tasks/{name}.yaml")
    if not old_text:
        return ["task-added-after-run"]
    old, changes = load(old_text), []
    kind = prompt_kind(old.get("prompt"), new.get("prompt"))
    if kind:
        changes.append(kind)
    if old.get("graders") != new.get("graders"):
        changes.append("graders")
    for key in VISIBLE_KEYS:
        if key == "environment" and runtime_only(old.get(key), new.get(key)):
            # Retargeting the simulator runtime (iOS 26.5 to 27.2, because the
            # old runtime was uninstalled) is not a change to the task. Results
            # on the old runtime are kept and the report says the runtimes mix.
            continue
        if old.get(key) != new.get(key):
            changes.append(key)
    others = {k for k in set(old) | set(new) if old.get(k) != new.get(k)} - INERT_KEYS - {
        "prompt", "graders", *VISIBLE_KEYS}
    if others:
        changes.append("other:" + ",".join(sorted(others)))
    fx = fixture_of(new)
    if fx:
        files = sh(taskset, "diff", "--name-only", commit, "--", f"Fixtures/{fx}",
                   ":!*.solution*", ":!*solution.patch", ":!*solution.yml", ":!*README.md").split()
        if files:
            changes.append(f"fixture({len(files)})")
    return changes


def failed_run(result, termination):
    return result == "FAIL" or termination not in (None, "completed")


def decide(result, changes, termination):
    if result is None:
        return "NEVER-RUN"
    if not changes:
        return "KEEP"
    if any(c.startswith("effort(") for c in changes):
        return "RERUN"
    if "prompt-added" in changes and failed_run(result, termination):
        # The prompt now says something the model was never told. A failure may
        # be exactly what the new sentence prevents, so it has to be rerun.
        return "RERUN"
    visible = [c for c in changes if c.startswith(("prompt-changed", "fixture", "environment", "repository",
                                                    "limits", "timeout", "setup", "withheld", "other", "no-baseline",
                                                    "task-added"))]
    failed = result == "FAIL" or termination not in (None, "completed")
    if visible and (failed or any(c.startswith(("prompt-changed", "fixture", "environment", "repository",
                                                "setup", "withheld", "no-baseline", "task-added")) for c in visible)):
        return "RERUN"
    if "graders" in changes and failed:
        return "RERUN"
    return "REVIEW"


def last_change(taskset, name, fx):
    paths = [f"Examples/Tasks/{name}.yaml"] + ([f"Fixtures/{fx}"] if fx else [])
    when = int(sh(taskset, "log", "-1", "--format=%ct", "--", *paths).strip() or 0)
    dirty = sh(taskset, "status", "--porcelain", "--", *paths).split("\n")
    for line in dirty:
        p = line[3:].strip()
        if p and (taskset / p).exists():
            when = max(when, int((taskset / p).stat().st_mtime))
    return when


def verification(reports, name):
    log = reports / "Logs" / "default" / f"{name}.log"
    if not log.exists():
        return None
    text = log.read_text(errors="replace")
    return (int(log.stat().st_mtime), bool(re.search(r"^verdict\s+PASS", text, re.M)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--taskset", default=os.environ.get("APPLEBENCH_TASKSET") or str(ROOT))
    ap.add_argument("--reports", default=str(_paths.reports_dir()))
    ap.add_argument("--model", action="append")
    ap.add_argument("--out", default=None)
    ap.add_argument("--suites-dir", default=str(ROOT / ".applebench/rerun-suites"))
    a = ap.parse_args()
    taskset, reports = pathlib.Path(a.taskset), pathlib.Path(a.reports)
    out = pathlib.Path(a.out or taskset / "Reviews" / f"{dt.date.today()}-rerun-inventory")
    names = sorted(p.stem for p in (taskset / "Examples/Tasks").glob("*.yaml"))
    tasks = {n: load((taskset / f"Examples/Tasks/{n}.yaml").read_text()) for n in names}

    # Verification status: last change newer than last passing verification log.
    unverified = {}
    for n in names:
        changed_at = last_change(taskset, n, fixture_of(tasks[n]))
        v = verification(reports, n)
        if v is None or v[0] < changed_at or not v[1]:
            unverified[n] = "no verification log" if v is None else (
                "verdict not PASS" if not v[1] else "changed after last verification")

    pf = ROOT / "Data" / "effort-policy.json"
    policy = json.loads(pf.read_text()).get("efforts", {}) if pf.exists() else {}
    cache, inventory = {}, {}
    for f in sorted(glob.glob(str(reports / "*.csv"))):
        slug = pathlib.Path(f).stem
        if a.model and slug not in a.model:
            continue
        latest = {}
        for r in csv.DictReader(open(f)):
            ts = run_instant(r["run_id"])
            if ts and (r["task"] not in latest or ts > latest[r["task"]][0]):
                latest[r["task"]] = (ts, r)
        rows = {}
        for n in names:
            if n not in latest:
                rows[n] = {"decision": "NEVER-RUN", "last": None, "changes": []}
                continue
            ts, r = latest[n]
            result = "PASS" if r["passed"] == "true" else "FAIL"
            changes = classify(taskset, n, tasks[n], ts, cache)
            wanted = policy.get(r["model"], "")
            if (r.get("effort") or "") != wanted:
                changes.append(f"effort({r.get('effort') or 'blank'}!={wanted or 'default'})")
            rows[n] = {"decision": decide(result, changes, r["agent_termination"]), "last": result,
                       "termination": r["agent_termination"], "run_id": r["run_id"], "changes": changes}
        inventory[slug] = rows

    out.mkdir(parents=True, exist_ok=True)
    json.dump({"unverified": unverified, "models": inventory}, open(out / "inventory.json", "w"), indent=1)
    lines = [f"# Rerun inventory, {dt.date.today()}", "",
             "Generated by `Scripts/rerun-inventory.py`. Decisions per model; REVIEW needs artifact proof or a regrade.", "",
             "| Model | RERUN | NEVER-RUN | REVIEW | KEEP |", "|---|---|---|---|---|"]
    for slug, rows in inventory.items():
        c = {k: sum(1 for r in rows.values() if r["decision"] == k) for k in ("RERUN", "NEVER-RUN", "REVIEW", "KEEP")}
        lines.append(f"| {slug} | {c['RERUN']} | {c['NEVER-RUN']} | {c['REVIEW']} | {c['KEEP']} |")
    blocked = {n: w for n, w in unverified.items() if w != "no verification log"}
    lines += ["", f"## Verification blocks ({len(blocked)})", "",
              "Changed after their last verification log, or the log's verdict was not PASS. "
              "Fail-then-pass must print `ok` before these are rerun or re-dated; they are held out of the rerun suites.", ""]
    lines += [f"- `{n}`: {why}" for n, why in blocked.items()]
    lines += ["", f"{len(unverified) - len(blocked)} further tasks have no verification log in "
              "`Reports/Logs/default/`; that is a gap in the record, not a failure.", ""]
    for slug, rows in inventory.items():
        lines += ["", f"## {slug}", "", "| Task | Last | Decision | Changes since the run |", "|---|---|---|---|"]
        for n, r in rows.items():
            if r["decision"] != "KEEP":
                lines.append(f"| {n} | {r['last'] or '-'} | {r['decision']} | {', '.join(r['changes']) or '-'} |")
    (out / "README.md").write_text("\n".join(lines) + "\n")

    suites = pathlib.Path(a.suites_dir)
    suites.mkdir(parents=True, exist_ok=True)
    for slug, rows in inventory.items():
        due = [n for n, r in rows.items() if r["decision"] in ("RERUN", "NEVER-RUN") and n not in blocked]
        (suites / f"{slug}-inventory.yaml").write_text(
            f"id: rerun-{slug}-inventory\nname: \"Inventory rerun {slug}\"\ntasks:\n" +
            "".join(f"  - {n}\n" for n in due))
    print(f"wrote {out}/README.md, inventory.json and {len(inventory)} suites in {suites} "
          f"({len(blocked)} blocked on verification, held back)")


if __name__ == "__main__":
    main()
