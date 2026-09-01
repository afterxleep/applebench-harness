---
title: Methodology
permalink: /methodology/
lede: >-
  How a run is executed, what is recorded, and the specific ways a benchmark
  like this can lie to you.
description: >-
  AppleBench's execution model, isolation guarantees, recorded variables, and
  the failure modes it is built to avoid.
---

## The run

```text
Task (YAML)
  ↓
AppleBench Runner        validates environment, creates isolated workspace
  ↓
AgentAdapter             launches the agent CLI non-interactively
  ↓
Agent modifies isolated workspace   (never sees grader configuration)
  ↓
Agent exits (or is terminated at the wall-clock limit)
  ↓
Independent AppleBench graders      fresh xcodebuild / tests / runtime checks
  ↓
result.json + events.jsonl + diff.patch
```

Every run gets a fresh clone at the exact task commit, verified clean before
the agent starts, and a dedicated simulator created for the run and deleted
afterwards. Grading never touches a dirty checkout from another run.

## The separation that matters

**Grader configuration is not written to disk until the agent has exited.**
While the agent is working, nothing in or near its workspace describes how it
will be evaluated. It cannot read the assertions and write to them.

**Grading uses fresh derived data.** The agent's own successful build never
counts as evidence. If the agent built it and the grader cannot, the grader
wins.

**The agent runs in a minimal environment.** `PATH`, `HOME`, `USER`, `TMPDIR`,
`SHELL`, `TERM`, `LANG`, `LC_ALL`, plus only the variables explicitly
allowlisted per run. Nothing else from the host shell leaks in. The agent's
own config is replaced by a benchmark-owned one that denies web access.

**Commands are spawned directly.** `posix_spawn`, never `sh -c`. Task YAML is
never interpolated into a shell string, so a task file cannot execute anything
by being cleverly written.

**The timeout is enforced by the harness, not the agent.** The child runs in
its own process group; on expiry the whole tree is terminated, the timeout is
recorded, and grading still runs against whatever the agent left behind.

## Isolation levels

| Level | What the agent can reach |
|---|---|
| Local | The workspace, plus the host filesystem. Suitable for trusted local runs. |
| Tart VM | Exactly two host folders: the workspace, read-write, and a read-only mount holding the agent config. Egress is denied by default and specific CIDRs can be opened. |

Under the VM, grading still happens on the host after the VM has been stopped.
The agent and the evaluator never share a running machine.

## What is recorded

Every run writes:

```text
.applebench/runs/<run-id>/
  workspace/       the agent's checkout
  events.jsonl     complete trajectory, one structured event per line
  result.json      stable machine-readable verdict and raw variables
  diff.patch       everything the agent changed, including untracked files
  metadata.json    task and environment snapshot (written after the agent exits)
  logs/            build logs, .xcresult bundles, screenshots
```

`result.json` carries the verdict, the task's category and difficulty, each
grader's outcome with duration and evidence, git change statistics, token and
cost usage as reported by the agent CLI, and trajectory metrics **derived from
the event log** rather than from anything the agent said about itself: tool
calls, commands executed, build and test invocations, output volume, and
phase durations.

## Honest about absence

Token counts and dollar cost are the three numbers the agent CLI genuinely
owns. They are extracted from its structured event stream and left `null` when
it did not report them.

**They are never zero-filled.** A `$0.00` on a chart means "not reported," not
"free," and the charts say so. Filling absent data with zeros would make a
model look cheaper the worse its telemetry is.

## Two failures that are not the same thing

A grader returning **FAIL** is a valid benchmark result. It counts in the
denominator.

A grader that **cannot execute**, because `xcodebuild` will not launch or the
`.xcresult` is malformed, is not a result at all. It is recorded as `errored`, excluded
from completion rates, and reported separately. Collapsing the two would let
a broken machine quietly deflate a model's score.

Similarly, an agent timing out and the final workspace passing are recorded as
two separate facts. An agent can exceed its budget and still have left the
repository in a working state; both things are true, and the record says both.

## Reading a published number

A pass rate is meaningless without its conditions. Every published run states:

1. **Which suite.** Scores come from the private gold set. The sample tasks
   that ship with the harness are for reading and copying, never for scoring.
2. **Which model, through which harness.** The harness is held constant so
   the model is the only variable.
3. **Which environment.** Xcode version and build, macOS version, simulator
   model and runtime.
4. **Which attempt counts.** When a task was re-run after an infrastructure
   failure, the selection rule changes the headline. A reader cannot infer it
   from the data, so it is stated.

That fourth one is the easiest to get wrong and the least visible. "Latest
attempt," "best attempt," and "first attempt" produce materially different
numbers from the same set of runs.

## Suite revisions

A pass rate is a fraction of a particular set of tasks. Change the set and the
number moves without any model having changed, so every published run records
the **suite revision** it was measured on, and results are only comparable
within one. A run measured on a superseded revision carries a banner saying so.

Each revision states what changed and why:

{% assign revisions = site.data.suite_revisions %}
{% for revision in revisions %}
### {{ revision.name }}{% if revision.current %} (current){% endif %}

{{ revision.gold_tasks }} scoring tasks. {{ revision.summary }}
{% if revision.changes %}
{% for change in revision.changes %}- {{ change }}
{% endfor %}{% endif %}
{% endfor %}

The bar a task has to clear to be in the set at all: it must fail for an agent
that changes nothing, and pass once the reference fix is applied. A task that
passes unfixed hands out free marks; one that fails even when fixed takes them
away whatever the agent did. Neither measures the model. The whole suite is
checked against that bar before a scoring run.

## Known limits

- **Difficulty is authored, not measured.** It is one person's comparative
  judgment within a category, and it is calibrated by observing which tasks
  models actually fail. Treat it as a label, not a metric.
- **Single-run results are noisy.** Agent behavior varies between runs on the
  same task. A single pass is weak evidence; `--runs N` exists for this reason.
- **The set is small.** 123 tasks is enough to see capability gaps by category
  and nowhere near enough for a significance claim. None is made.
- **Cost depends on the provider's reporting.** Two models are only cost-
  comparable if both report usage, through the same harness, in the same run.
