# Results, artifacts, and suites

## What gets measured

Every run produces `result.json` (stable, machine-readable) and
`events.jsonl` (the full trajectory). The runner **derives** counts and
durations from what it observed, never from agent self-reporting, except
for the three numbers the agent CLI genuinely owns (`inputTokens`,
`outputTokens`, `estimatedCostUSD`), which are extracted from the structured
event stream and left `null` where the agent did not report them.

### Per-run variables in `result.json`

| Field | Type | Source | Notes |
|---|---|---|---|
| `schema_version` | int | constant (`1`) | Bump on breaking changes. |
| `run_id` | string | derived | `<UTC timestamp>-<task>-<agent>` |
| `task`, `category`, `difficulty`, `tags` | string/enum/int/[string] | task YAML | `category` and `difficulty` propagate to `results` grouping. |
| `agent` | object | adapter | `agent`, `model`, `version`, `configuration` (no secrets) |
| `environment` | object | snapshot | `macos`, `architecture`, `xcode`, `xcode_build`, `simulator`, `runtime` |
| `result.passed` | bool | all graders | `true` only when every required grader passed. |
| `result.duration_seconds` | double | `ContinuousClock` | Wall-clock for the whole run. |
| `result.agent_termination` | string | adapter | `completed` / `timeout` / `failed` / `cancelled`, kept distinct from `passed`. |
| `usage.input_tokens` | int? | OpenCode JSON `tokens.input` | `null` if the agent did not report it. |
| `usage.output_tokens` | int? | OpenCode JSON `tokens.output` | `null` if the agent did not report it. |
| `usage.total_tokens` | int? | sum of the above, when both are present | `null` otherwise, never zero. |
| `usage.estimated_cost_usd` | double? | OpenCode JSON `cost` | `null` if not reported. |
| `metrics.total_events` | int | event stream | Lines in `events.jsonl`. |
| `metrics.agent_events` | int | event stream | Lines classified as `agent_event`. |
| `metrics.tool_calls` | int | event stream | Of those, the lines where `kind == "tool_call"`. |
| `metrics.agent_output_chunks` | int | event stream | `agent_output` events. |
| `metrics.agent_output_bytes` | int | event stream | UTF-8 byte total of `text` fields. |
| `metrics.commands_executed` | int | event stream | `command_finished` events. |
| `metrics.build_invocations` | int | event stream | `command_finished` where the command contains `xcodebuild` and not ` test`. |
| `metrics.test_invocations` | int | event stream | `command_finished` where the command contains both `xcodebuild` and ` test`. |
| `metrics.agent_duration_seconds` | double? | event stream | `agentFinished.timestamp - agentStarted.timestamp`. |
| `metrics.grading_duration_seconds` | double? | event stream | `runFinished.timestamp - gradingStarted.timestamp`. |
| `graders` | array | grader output | One entry per task grader with `name`, `passed`, `duration_seconds`, `summary`, `evidence[]`. |
| `git.base_commit` | string | runner | The SHA the agent started from. |
| `git.final_commit` | string? | runner | If the agent's HEAD moved. |
| `git.files_changed`, `git.insertions`, `git.deletions` | int | `git diff --numstat` | Including untracked files. |
| `artifacts` | object | layout | `events.jsonl`, `diff.patch`, `logs/`. |

Points are not stored in `result.json`. They are derived at export time from
the empirical task weights and `result.passed`, so a scoring revision never
requires rewriting a run's record. The CSV export adds `face_value` (the
task's empirical weight) and `points`; the JSON export adds a `score` object
at the top level and on every category and configuration, plus the
`task_weights` map the score was computed from.

### Scoring: AppleBench points (empirical-v1)

A pass rate says how many tasks were completed. The empirical score says how
much of the suite's demonstrated difficulty was completed: tasks that every
complete published model passes count for little, and passes almost nothing
manages count for a lot. Resource efficiency remains separate so price or
provider latency cannot change a capability verdict.

```text
weight      = min(2000, round(100 × modelCount / passingModelCount))
            (a task no complete model passes earns the 2000-point cap)
face value  = weight
points      = passed ? face value : 0

score       = 100 × Σ points / Σ face value
```

Implemented in `Sources/AppleBenchCore/Models/BenchmarkScore.swift`, frozen
under a specification id (`empirical-v1`) that every export records. The
weights themselves are published at `site/_data/empirical_weights.json` and
recorded inside every report JSON under `task_weights`.

| Rule | Why |
|---|---|
| Weight comes from observed pass rates, not authored difficulty | The weighting is a measurement of the field, not an editorial judgment. `difficulty` stays in raw metadata but never scores. |
| Every task is binary | A pass earns the full weight; a failure earns 0. There is no partial credit. |
| A failure keeps its weight in `available` | The denominator is a property of the suite, so it does not move as a model gets better or worse. |
| A task no model passes earns the 2000-point cap | Unmet difficulty stays in the denominator and rewards whoever eventually clears it. |
| Only complete published runs for the current suite set the weights | A partial or in-progress run must not shift anybody's score. |
| Adding a complete model rescores every complete model | The new entrant can change the pass rates, so the weights — and every earlier score — are recomputed without rerunning anything. |
| A run for a task with no recorded weight is `unscored` | It contributes to neither side and is counted separately rather than handed a guessed weight. |
| Cost and active time never change points | Capability and resource efficiency remain independently inspectable. |

**Scores are additive across task sets.** Within one weight snapshot each
task's contribution depends only on its own weight and verdict, so
`score(A) + score(B) == score(A + B)`. That is what makes the suite
extensible: when a task set is added, existing models are run **against the
new tasks only** and the points are added to what is published. No previously
measured task is re-run. What *can* change without a rerun is the weighting:
publishing a new complete model shifts the observed pass rates, so
`Scripts/rescore-empirical.py` recomputes the weights and every model's score
from the same verdicts. `Tests/AppleBenchCoreTests/BenchmarkScoreTests.swift`
pins the additive property.

Adding a task set, end to end:

```bash
# 1. Run the new tasks only, for each model already published.
applebench suite gold-02 --model minimax/MiniMax-M3

# 2. Export the old and new runs together. `results` walks the tree, so
#    pointing it at a parent of both directories sums them.
./Scripts/publish-report.sh gold-2026-11-01 .applebench/runs gold \
    --attempt first --model minimax/MiniMax-M3
```

Changing a constant is a scoring revision, not a re-run: every published number
is recomputed from its stored `Reports/<slug>.json`.

### Which attempt counts

A run directory can hold several attempts at the same task. `first`, `latest`
and `best` produce materially different headlines from the same data and a
reader cannot infer which was used, so the rule is chosen at export time and
recorded in the export:

```bash
applebench results .applebench/runs --attempt first --model minimax/MiniMax-M3
```

| Option | Effect |
|---|---|
| `--attempt all` | Default. Every run counts; a re-run task carries more weight. |
| `--attempt first` | The earliest attempt per task per configuration. |
| `--attempt latest` | The most recent attempt. |
| `--attempt best` | The earliest passing attempt, or the earliest attempt when none passed. |
| `--model <id>` | Restrict to one model, for a directory holding several. |

Selection is keyed on the task **and** the configuration, so one model's run can
never supersede another's.

### Per-task grade semantics

- A grader returning `passed = false` is a **valid benchmark result** and is
  included in completion-rate denominators.
- A grader that **cannot execute** (e.g. `xcodebuild` reports a malformed
  `.xcresult`) is **not** the same thing, the runner records it as
  `graderFailure`, counts it as `errored`, and stops the suite before another
  task is claimed. Completed valid results are retained and excluded errors do
  not affect the completion rate. After fixing the infrastructure, rerun with
  `--changed` to resume from the errored task.

### Suite-level aggregation

`applebench suite` runs every task for every entry (one per `--model`) and
prints, per configuration:

```text
                                  Score     Passed   Completion  Tokens    Cost      Cost/point
opencode · anthropic/claude-...   47/52     9/10     90.0%       412809    $1.2041   $0.0256
opencode · openai/gpt-5           41/52     8/10     80.0%       688112    $1.8722   $0.0457
```

`applebench results` reads the on-disk `result.json` files and groups by
category first, so a weak capability is visible rather than averaged away.
Runs from tasks that predate the category schema fall into an explicit
`uncategorized` group rather than being silently folded into one of the six.

## Run artifacts

```text
.applebench/runs/2026-08-16T105500-runtime-002-opencode/
  workspace/       the agent's checkout (kept with --keep-workspace or on failure)
  events.jsonl     complete trajectory, one structured event per line
  result.json      stable machine-readable verdict + raw variables
  diff.patch       everything the agent changed, including untracked files
  metadata.json    task + environment snapshot (written only after the agent exits)
  opencode.json    the hermetic agent configuration used for this run
  logs/            agent-output.log plus grader evidence: build logs,
                   .xcresult bundles, screenshots
```

`result.json` includes the verdict, the task's category and difficulty,
per-grader outcomes with durations and evidence, git change stats,
token/cost usage as reported by the agent CLI (`null` when unavailable, never guessed), and trajectory metrics derived from the event log: tool
calls, commands executed, build/test invocations, output volume, and phase
durations.

The trajectory grader also rejects agent tool inputs that explicitly reach
the harness checkout outside the current workspace. System toolchain, Xcode,
DerivedData, and temporary paths remain valid; paths in compiler output, and
source text an agent writes or edits into a file, are not treated as agent
requests.

Every run gets that check, not only tasks that declare a trajectory grader:
the runner adds a `trajectory` result to any task without one.

Before every `xcodebuild test` a grader runs, including both runs of a mutation
grader, the app under test is uninstalled from the run's simulator and its
privacy grants are reset, so one grader's saved state or granted permission
cannot decide the next. A mutation grader also skips the tests the task's own
test graders skip. `remove_before` on an xctest or xcuitest grader deletes the
listed workspace paths before the tests run.

When the test target does not compile, the test grader's summary names the
first compiler error (`Tests failed to compile: ...`) instead of reporting that
no tests executed.

A UI flow grader judges only a screen that shows the app's own content. When a
read shows the home screen or a blank screen, it relaunches the app; when a
step fails while the app is not on screen, it relaunches and drives the flow
once more. An app that never appears is an infrastructure failure, not a
failed task.

A provider that stops a working agent for account or service reasons (HTTP
401, 402, 403, 429 or 5xx) produces no result: the suite stops as an
infrastructure error and `--changed` runs the task again.

An agent timing out and the final workspace passing are recorded as two
separate facts (`result.agent_termination` vs `result.passed`), never
collapsed.


## Suites

```bash
applebench suite core   --models anthropic/claude-sonnet-5,openai/gpt-5 --runs 5
applebench suite smoke  --model anthropic/claude-sonnet-5
applebench suite visual --model anthropic/claude-sonnet-5
```

`Examples/Suites/` ships:

- **`gold`**, private scoring set. Published scores must use this.
- **`dev`**, 8 public tasks. Expected to leak. Never scored.
- **`all-benchmark`**, gold plus dev, local verification only.
- **`core`**, app-building gold (no ops, UI-automation, or frameworks).
- **`build`**, **`tests`**, **`runtime`**, **`visual`**, **`interaction`**,
  **`project`**, **`frameworks`**, **`ops`**, one category.
- **`smoke`**, one gold task per category.

Tasks run sequentially (no parallel simulator contention), each in its own
workspace and simulator. Aggregate output is raw sums and rates per
configuration, plus the AppleBench points score described above. No statistical
significance claims are made.

Runs that fail for infrastructure reasons (agent CLI missing, `xcodebuild`
unlaunchable) stop before another task is claimed. They are counted separately
as *errored* and excluded from completion rates. Completed valid results remain
publishable so `--changed` can resume after the issue is fixed. A grader
reporting FAIL is a valid benchmark result and does not stop the suite; a grader
that cannot execute is not.

## Run limits and safety

- The wall-clock timeout is enforced by AppleBench: on expiry the agent's
  entire process tree is terminated (the child runs in its own process group),
  the timeout is recorded, and grading still runs against whatever remains.
- Commands are spawned directly (`posix_spawn`), never through `sh -c`; task
  YAML is never interpolated into shell strings.
- Agents run with a minimal environment (`PATH`, `HOME`, and friends) plus an
  explicit allowlist (`--allow-env NAME`, repeatable). Unrelated secrets are
  not exposed by default.
- Agents are autonomous processes that can run arbitrary commands on this
  machine. v1 is trusted-local-machine tooling: run it on hardware you trust
  with checkouts you accept executing.


## Publishing a run

```bash
./Scripts/publish-report.sh <slug> [runs-dir] [suite] [--attempt RULE] [--model ID]
```

The page writes itself. Everything on it, the model, the harness and how it
was configured, the host, the score and the specification it was computed under,
the pass rate, the per-category and per-difficulty charts, the per-task table,
is read from the run's own export at build time, so a published page cannot
drift from the data it links to. Points are computed by the harness and exported
per row, not derived in the page template, for the same reason.

`--attempt` defaults to `first`, the strictest reading.

To re-export a run whose workspaces have been cleaned up, restore its runs tree
from the archived summary first:

```bash
python3 Scripts/import-run-summary.py Reports/<slug>.json .applebench/archive/<slug>
```

It produces:

```text
Reports/<slug>.csv                  full per-run detail
Reports/<slug>.json                 aggregate totals plus every run
site/_data/benchmarks/<slug>.csv    the chart source
site/_data/reports/<slug>.json      conditions and totals
site/_benchmarks/<slug>.md          the published page
```

The front matter is generated, including the current `suite_revision`. A run
measured on a superseded revision is marked as such on its own page, because
a pass rate is a fraction of a particular set of tasks and moves when the set
does.

Commentary is optional and goes in the body, below the front matter;
re-publishing a run refreshes the facts and leaves what you wrote alone,
including a `lede:` in the front matter. The one thing worth writing by hand is
*why* this attempt rule and what was excluded — the export states which rule ran,
but not the reasoning, and the headline depends on it.

If a run directory holds more than one configuration, the page breaks them
out rather than reporting a single rate over the mixture.
