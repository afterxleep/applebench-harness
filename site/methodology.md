---
title: Methodology
permalink: /methodology/
kicker: AppleBench / Methodology
lede: >-
  How a run is executed, what is recorded, and the specific ways a benchmark
  like this can lie to you.
description: >-
  AppleBench's execution model, isolation guarantees, recorded variables, and
  the failure modes it is built to avoid.
---

{% assign current_suite = site.data.suite_revisions | where: "current", true | first %}

<nav class="article-index" aria-label="On this page">
  <p>On this page</p>
  <ol>
    <li><a href="#the-run">The run</a></li>
    <li><a href="#the-separation-that-matters">Separation</a></li>
    <li><a href="#isolation-levels">Isolation</a></li>
    <li><a href="#what-is-recorded">Recorded evidence</a></li>
    <li><a href="#scoring">Scoring</a></li>
    <li><a href="#grading-against-the-device">Device grading</a></li>
    <li><a href="#reading-a-published-number">Reading a result</a></li>
    <li><a href="#suite-revisions">Suite revisions</a></li>
    <li><a href="#known-limits">Known limits</a></li>
  </ol>
</nav>

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

## Reading the results

AppleBench does not collapse capability, money, and time into one authored
score. The results keep those measurements separate:

- **Pass rate** is the primary capability result: verified passes divided by
  attempted tasks.
- **Cost per verified pass** is total recorded list-price spend divided by
  verified passes. Failed attempts remain in the numerator because they still
  cost money.
- **Active time per verified pass** is total time in the agent phase divided by
  verified passes. It is operational evidence, not a capability penalty,
  because provider latency contributes to it.
- **Suite cost and wall-clock time** show the absolute resources consumed.

Tokens and tool calls remain available for diagnosis. They are not ranking
inputs: token prices vary by model, and raw tool-call counts can punish useful
build/test loops or be reduced by batching unrelated shell work.

The leaderboard is ordered by pass rate. Cost and active time sit beside it so
their tradeoffs remain visible without choosing arbitrary weights. Results are
only compared within the same suite revision and attempt rule.

A task still carries an authored difficulty label to describe the kind of work.
That label does not change its contribution to pass rate.

## Grading against the device

Every grader described above asks `xcodebuild` a question, which means the
suite only ever sees an app in one state: portrait, English, light, default
text size, hardware keyboard attached. That is the state the people who wrote
the app were in. A defect that only appears outside it is invisible to the
whole apparatus, and that covers a great deal of what users actually report:
a layout that breaks when the phone turns, a list that files two names wrongly
in Swedish, a button the keyboard sits on top of.

A second kind of grader asks the device instead. It builds and installs the
app, puts the simulator into a named state, drives the app, and judges the
accessibility tree it leaves.

**Why this needs the device and not a test target.** Appearance, Dynamic Type
and contrast have `simctl` equivalents. Orientation and system language do
not: rotation is a GSEvent plus a poll of the device's own preferences until
the physical orientation actually matches, and language is a write to the
global preferences plist followed by a reboot. Hardware buttons have no
`simctl` verb at all: Home, lock, the app switcher.

**The assertions live outside the workspace.** They are written in the task
file, not in a test target, so a fixture graded this way ships with no tests
at all. The agent receives an app with nothing in it describing how it will be
judged. What can be asserted is deliberately small and entirely mechanical:
text present or absent, rows in a given order reading down the screen, an
element inside the window, a minimum size, two elements not overlapping, one
element clear of another, the device's physical orientation.

**Colour is the exception, and it is answered by comparison rather than by a
reference image.** An accessibility tree carries labels, values and frames; it
carries nothing about how anything looks, so a hardcoded palette used to be
ungradeable here. It does not need a golden file or a tolerance anyone has to
tune. A screen reading semantic colours **renders differently** in light and
dark. A screen with its colours written in renders the same picture twice, and
that is the check.

**Each task is graded in both states.** The state the defect appears in, and
the default one it was written in. A fix that works rotated and breaks upright
fails, and so does a fix that pins the behaviour to one language instead of
following the reader's.

**The data is pinned separately.** Driving the app proves what it does; it
cannot prove *why* it does it. An agent can make a name fit by shortening the
name, make a count right by deleting the row that made it wrong, or make a
Turkish casing bug irrelevant by upper-casing the data it operates on. Where
that is possible the task also asserts, as text, that the data the defect
depends on is still there.

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

### Reasoning effort

**Every model is run at the strongest reasoning it exposes.** The point is to
measure what a model can do, not which setting it happened to be given, and a
model held at a lower effort than a rival is not being compared with it.

The ladder is not the same everywhere. Some models take `low` through `max`,
some only toggle reasoning on and off, and some expose no selectable level at
all. So the level comes from a pinned catalog of what each model actually
offers rather than from a hardcoded word. Asking a model for an effort it does
not have is not a stronger run; it is an invalid request.

Where a model exposes no ladder, the run page says so. It does not report
"maximum", because there is no such setting to have chosen, and a report that
claimed one would be describing a decision nobody made.

### Cost

**Cost is the model owner's list price**, from a pinned snapshot of
[models.dev](https://models.dev), the same registry the agent CLI reads. Every
run page states the retrieval date. The price is pinned rather than fetched, so
a published score does not move when a provider changes its rates; refreshing
it is a deliberate act that shows up as a diff.

Two token categories, because they bill differently. Fresh input and output are
charged at the headline rate. **Cached prompt tokens** are the conversation an
agent re-sends on every step. They are charged at a much lower cached rate, and
they are the majority of what an agentic run reads: roughly seven cached tokens
for every fresh one here.

That ratio is why the token figure on a run page is input and output only, and
excludes cache. It means "what the model produced and was newly given" rather
than "how long the conversation got"; cost still includes cached input.

A caution learned the hard way: a cost computed from a token count that is
missing a category is wrong by multiples, not by rounding. This benchmark
published one for a few hours that was five times too low, because cached
tokens were being dropped. The check that catches it is comparing the computed
figure against what the agent CLI independently reports. They should agree to
the cent, and a gap means a category is missing.

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
- **The set is small.** {{ current_suite.gold_tasks }} tasks is enough to see capability gaps by category
  and nowhere near enough for a significance claim. None is made.
- **Cost depends on the provider's reporting.** Two models are only cost-
  comparable if both report usage, through the same harness, in the same run.
