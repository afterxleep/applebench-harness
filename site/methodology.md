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

## Scoring

A pass rate answers one question — how many did it get right — and then stops.
Two models can complete the same task and be nothing alike. One reads the build
log and edits two lines. The other rebuilds the project eleven times, argues
with `simctl`, and burns three quarters of a million tokens arriving at the same
diff. A pass rate gives them the same tick.

So the headline number is **points**, and the pass rate stays beside it.

```text
face value  = 10 × difficulty                     difficulty 1–10 → 10–100 points
budget      = 50,000 total tokens                 flat, the same for every task
efficiency  = clamp(budget / tokens, 0.25, 1.0)   unreported tokens → 0.25
points      = passed ? face value × efficiency : 0

score       = Σ points          available = Σ face value
```

**Difficulty scales the reward, not the allowance.** The obvious move is to give
harder tasks a bigger token budget. The data does not support it: across the
first scored run the median solve cost between 14k and 26k tokens at every
difficulty from 1 to 7. Spend does not track authored difficulty, so scaling
the allowance by difficulty would encode a relationship that is not there.
Difficulty decides what a task is worth; every task gets the same allowance.

**A failure earns nothing and still counts its face value.** The denominator is
a property of the suite, not of the model, so it does not move as a model gets
better or worse.

**A wasteful solve still beats a failure.** The 0.25 floor is there because
doing the work badly is not the same as not doing it.

**Unreported tokens take the floor.** For the same reason a missing cost is left
blank rather than written as `$0.00`: if absence took the favourable value, a
model would score better the worse its telemetry was. The count of solves
scored this way is published on the run's page.

### The constants are authored, and frozen

50,000 tokens and the 0.25 floor are judgment, not measurement, chosen so an
ordinary solve is not penalized and genuine overspend is. They are frozen under
a specification id — currently `points-v1` — and every published run records
which one it was scored under. Changing a constant is a scoring revision, and
every published number is recomputed from its stored export. That does not
require re-running any benchmark.

### Why the score is a plain sum

Every term depends only on the task it belongs to: its authored difficulty, its
verdict, and what that run spent. Nothing is normalized against the rest of the
set, against other models, or against how many tasks the suite happens to hold.

That is deliberate, and it is what makes the suite extensible. When a task set
is added, the existing models are run **against the new tasks only**, and their
points are added to what is already published. Nothing already measured is
re-run, and no previously published per-task number changes. A model that has
not been run against the new set is not silently penalized either — it is
reported against the set it was actually measured on, which is what the suite
revision has always recorded.

### What points do not tell you

They do not compare across suite revisions, they do not compare across scoring
specifications, and they are not a dollar figure. Cost and wall-clock time are
reported separately and unweighted, because provider pricing changes and a
score that moved with it would be measuring the wrong thing.

## Reading a published number

A score is meaningless without its conditions. Every published run states:

1. **Which suite, and which scoring specification.** Scores come from the
   private gold set. The sample tasks that ship with the harness are for
   reading and copying, never for scoring.
2. **Which model, through which harness, at what reasoning effort.** The
   harness is held constant so the model is the only variable, and effort is
   stated because a model at high effort and the same model at low effort are
   two different results.
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
