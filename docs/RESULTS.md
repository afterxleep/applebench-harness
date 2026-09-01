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

### Per-task grade semantics

- A grader returning `passed = false` is a **valid benchmark result** and is
  included in completion-rate denominators.
- A grader that **cannot execute** (e.g. `xcodebuild` reports a malformed
  `.xcresult`) is **not** the same thing, the runner records it as
  `graderFailure` and the run terminates with exit code 2 (`BenchmarkFailure`).
  Suite aggregation counts these as `errored` and excludes them from the
  completion rate.

### Suite-level aggregation

`applebench suite` runs every task for every entry (one per `--model`) and
prints, per configuration:

```text
                                  Passed   Completion  Median   Tokens    Cost      Cost/solve
opencode · anthropic/claude-...   9/10     90.0%       4m 12s   412809    $1.2041   $0.1338
opencode · openai/gpt-5           8/10     80.0%       6m 03s   688112    $1.8722   $0.2340
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
workspace and simulator. Aggregate output stays descriptive, raw sums and
rates per configuration, no composite score, no statistical significance
claims.

Runs that fail for infrastructure reasons (agent CLI missing, `xcodebuild`
unlaunchable) are counted separately as *errored* and excluded from completion
rates, a grader reporting FAIL is a valid benchmark result; a grader that
cannot execute is not.

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
  with checkouts you accept executing. Interfaces are designed so VM-based
  isolation can be added later.


## Publishing a run

```bash
./Scripts/publish-report.sh <slug> [runs-dir] [suite]
```

The page writes itself. Everything on it, the model, the harness and how it
was configured, the host, the pass rate, the per-category and per-difficulty
charts, the per-task table, is read from the run's own export at build time,
so a published page cannot drift from the data it links to.

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
re-publishing a run refreshes the facts and leaves what you wrote alone. The
one thing worth writing by hand is which attempt counts when a task was
re-run, the data cannot say it, and the headline depends on it.

If a run directory holds more than one configuration, the page breaks them
out rather than reporting a single rate over the mixture.
