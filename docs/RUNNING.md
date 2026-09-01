# Running the suite

A scoring run on a clean macOS VM, from nothing to a published page.

## What the VM needs

| | |
|---|---|
| macOS | Apple Silicon, recent enough for the Xcode below |
| Xcode | any version that provides the runtime below, selected with `xcode-select` |
| Simulator runtime | **iOS 26.5**, with an `iPhone 17` device type |
| Swift | 6 language mode, ships with Xcode 16 and later |
| XcodeGen | `brew install xcodegen`, required to prepare fixtures and to grade an isolated one |
| OpenCode | `brew install sst/tap/opencode` |
| Tart + sshpass | `brew install cirruslabs/cli/tart sshpass`, only for `--vm`, which is the one mode that enforces isolation |
| Disk | 30 GB free is comfortable |

**No task pins an Xcode version.** `environment.xcode` exists in the task
schema and is enforced when set; no task sets it. What every task does name is
a simulator (`iPhone 17` on `iOS 26.5`), and that is the only thing tying the
suite to a recent Xcode.

### Running on an older Xcode

The floor for the harness itself is **Xcode 16**: it is a Swift 6 package and
uses `xcresulttool get test-results`, both of which arrived there. The
fixtures deploy to iOS 18.0, carry no availability annotations, and use no API
newer than that.

So point the suite at a runtime your Xcode has, rather than editing every task
file:

```bash
export APPLEBENCH_SIMULATOR_DEVICE="iPhone 16"
export APPLEBENCH_SIMULATOR_RUNTIME="iOS 18.5"
```

The task files keep naming the reference environment, the override says what
this host actually ran, and each run records the environment it really used, so a published result is never ambiguous about which it was.

Verify before scoring on a toolchain the suite has not been proven on:

```bash
./Scripts/verify-fixtures.sh
```

### What has been verified where

| Toolchain | Coverage |
|---|---|
| Xcode 27.0 beta 6 (27A5252f), iOS 26.5 / iPhone 17 | all 123 gold tasks |
| iOS 18.5 / iPhone 16 runtime, same Xcode | 15 tasks across every category, build, tests, runtime, visual, interaction, ui-auto, project, ops, and six framework families, all fail-then-pass |

The iOS 18 sample is the runtime an Xcode 16 host would provide. It does not
prove the compiler behaves identically, only that nothing in the fixtures
needs a newer SDK.

Treat a failure on an unverified toolchain as a difference to investigate
rather than a model result. Framework behaviour does move between releases:
SwiftData's predicate translation traps on expressions it cannot lower, and
that is exactly the sort of thing that shifts.

Several tasks crash the app on purpose, and macOS puts a "quit unexpectedly"
dialog on screen for each one. Over a suite that is a modal dialog per crashing
task:

```bash
defaults write com.apple.CrashReporter DialogType none
# undo with: defaults delete com.apple.CrashReporter DialogType
```

`run-benchmark.sh` checks this and says so rather than writing the preference
itself, since it is a global user setting.

Accept the license and install the runtime before anything else:

```bash
sudo xcodebuild -license accept
xcodebuild -downloadPlatform iOS          # then confirm 26.5 is present
xcrun simctl list runtimes | grep "iOS 26.5"
xcrun simctl list devicetypes | grep "iPhone 17"
```

## Get the harness and a task set

The harness is public. The tasks it runs live in their own repository, so on a
fresh machine a scoring run is:

```bash
git clone https://github.com/afterxleep/applebench-harness.git
cd applebench-harness

./Scripts/run-benchmark.sh \
  --task-set-repo git@github.com:you/your-scoring-set.git \
  --model <model> \
  --api-key-file ~/.config/applebench/openrouter.key \
  --strip-wrapper-clis
```

That clones the task set into `.applebench/taskset`, prepares its fixtures, and
runs the `gold` suite. Later runs fast-forward the clone instead of re-cloning,
and a task set that has diverged locally is an error rather than a merge, since
a merged set is a different set and would score different tasks. Put the URL in
`APPLEBENCH_TASKSET_REPO` and you can drop the flag.

Run it with no `--task-set-repo` at all and the eight bundled sample tasks are
what runs, so a fresh clone works with no arguments.

For a task set already on disk, point at it directly and prepare it yourself:

```bash
export APPLEBENCH_TASKSET=/path/to/scoring-task-set
./Scripts/prepare-fixtures.sh
```

Nothing is copied in either direction. The clone, prepared fixtures, run
artifacts and reports all live under the harness's `.applebench/`, so the task
set stays clean and a closed one never lands in a public checkout.

## Prepare

```bash
swift build -c release
./Scripts/prepare-fixtures.sh
```

`prepare-fixtures.sh` snapshots every fixture into `.applebench/fixtures/`,
strips the authoring files, and withholds the graded tests for the fixtures
that isolate. Run it again whenever a fixture changes.

Optional, and worth it before a run you intend to publish. It takes a few
hours and proves every task still fails unfixed and passes fixed:

```bash
./Scripts/verify-fixtures.sh
```

## Run

The model identifier is passed through to OpenCode, so an OpenRouter model is
named `openrouter/<publisher>/<model>`.

```bash
./Scripts/run-benchmark.sh \
  --suite gold \
  --model openrouter/anthropic/claude-sonnet-4.5 \
  --task-set-repo git@github.com:you/your-scoring-set.git \
  --api-key-file ~/.config/applebench/openrouter.key \
  --strip-wrapper-clis
```

### Bounding what a run costs

Most of a suite's spend is in the tasks a model cannot solve, because those are
the ones that run to their full limit. Two caps bound that from the command
line, so the task files stay as their author wrote them:

```bash
./Scripts/run-benchmark.sh --suite gold --model <model> \
  --max-tokens 150000 --timeout-cap 600
```

`--max-tokens` counts spend live from the agent's own usage reports and tears
down the process when it crosses the budget. The run records
`budget_exceeded` rather than `timeout`, so a reader can tell which limit ended
it. Grading still runs against whatever the agent left, exactly as it does
after a timeout.

It is a step boundary, not a hard ceiling. OpenCode reports usage per completed
step, so the earliest the harness can act is after the step that crossed the
line; a cap of 500 against a first step of 20,000 stops after that step, not at
500. It bounds how many steps a losing task gets, which is where the money goes,
not the exact token count.

`--timeout-cap` is the same idea for the clock. Both only ever tighten: a task
asking for less than the cap keeps what its author gave it, because raising a
limit would change what the task measures.

### Reasoning effort

`--effort` sets how hard the model thinks, forwarded to OpenCode as the model
variant:

```bash
./Scripts/run-benchmark.sh --suite gold --model <model> --effort high ...
```

Which levels exist is up to the provider (`minimal`, `low`, `medium`, `high`,
`max` are the usual set), so the value is passed through rather than validated.
An unknown level fails at the agent, not silently.

Effort changes the number, so it is part of a run's conditions rather than a
detail: each run records it as `variant` in its metadata, and two runs at
different efforts are not comparable. `--agent-arg` forwards anything else to
the agent CLI verbatim, repeatably, for knobs `--effort` does not cover.

`--api-key-file` reads the key, puts it in the environment as
`OPENROUTER_API_KEY`, and allowlists it for the agent. `--api-key <key>` takes
it inline instead, at the cost of putting a secret where `ps` and your shell
history can see it. Either way you no longer have to remember to export the
variable *and* pass `--allow-env` for it, which is the mistake that looks
exactly like a bad model: the agent launches, cannot authenticate, and every
task fails.

Setting `OPENROUTER_API_KEY` yourself and passing `--allow-env` still works.

`--strip-wrapper-clis` hides `flowdeck`, `tuist`, `fastlane`, `xcodegen` and
friends from the agent's `PATH`. Use it: the benchmark is about driving the
Apple toolchain, and a wrapper answers a different question. That mode also
gives the agent a hermetic `HOME`, so credentials stored by `opencode auth
login` are not visible to it, which is why the key is passed with
`--allow-env` rather than relied on from disk.

That command runs the agent as a process on this host. Read the next section
before publishing anything from it.

## Isolating the agent

There are two levels here and they are not the same claim.

**On this host, the default.** The agent gets a benchmark-owned OpenCode config
in place of the user's, `webfetch` denied, plugins off, and no user MCP servers
or instructions. That removes the agent's network *tool*. It does not isolate
the *process*: `bash` is allowed and `curl` is on `PATH`, so an agent that
wanted a web page could still fetch one. Fine for development. Not something to
describe as sandboxed.

**In a VM, the enforced one.** `--vm` runs the agent inside a Tart guest with
Softnet default-denying every destination (`--net-softnet-block=0.0.0.0/0`).
The guest sees exactly two paths from this host: the workspace, read-write, and
the harness's own OpenCode config, read-only. The harness, the graders, your
task set and the rest of the filesystem are not mounted and cannot be reached.
Grading still happens on the host, against the workspace, after the VM stops.

```bash
brew install cirruslabs/cli/tart sshpass

./Scripts/run-benchmark.sh \
  --suite gold \
  --model <model> \
  --vm applebench-runner:latest \
  --vm-allow 203.0.113.0/24        # omit entirely for a fully offline guest
```

A hosted model needs a route to its provider, so `--vm-allow` opens that range
and nothing else. The block stays in place underneath, so an allow narrows the
denial rather than lifting it. A guest running a local model needs no
`--vm-allow` at all, and that is the only configuration where the agent has no
network whatsoever.

Passing `--vm-allow` without `--vm` is refused rather than ignored, because it
reads as "isolated except for this range" while describing a completely
unisolated run.

### Preparing the image

Tart images are yours to build; the harness only boots one. It needs Xcode with
the simulator runtime the tasks name, `opencode` on `PATH`, an SSH user the
`--vm-user` / `--vm-password` flags match, and any model credentials already
authenticated inside the guest, since a default-deny guest cannot go and fetch
them.

### What the run records

Every run writes which mode it used, so a published number is never ambiguous
about it. A VM run records `isolation: tart-vm`, the image, and the exact
network policy. A host run records `isolation: none (host process)` and
`network: unrestricted (host egress)`. Check `result.json` before publishing:
if it says the second thing, the run was not sandboxed, whatever the agent's
own toolset was told.

Leave `--parallel` at 1. Each slot runs a full task with its own simulator,
and simulators running alongside each other is the single most reliable way
to turn a good run into a directory of timeouts.

Expect several hours for 123 tasks. The script writes a log and a summary to
`Reports/gold-<date>/` and exits with the suite's own status.

### Pointing at something else

To route through a self-hosted or proxied endpoint, export an OpenCode
provider block before running, inline JSON or a path to a JSON file:

```bash
export APPLEBENCH_OPENCODE_PROVIDER='{"local":{"npm":"@ai-sdk/anthropic", ...}}'
```

The block is merged into the harness's own configuration, which re-applies
its sandbox keys afterwards: an override cannot re-enable web access.

## Publish

```bash
./Scripts/publish-report.sh 2026-09-01-sonnet-45 .applebench/runs gold
```

The page writes itself from the run's export, model, harness, host, pass
rate, charts, per-task table. Add commentary in the body only if there is
something the numbers do not say; the one thing worth writing by hand is
which attempt counts, when a task was re-run.

Then commit and push; the Pages workflow deploys on any change under
`site/`.

## If a run goes wrong

- **Everything after a certain point timed out.** Almost always another
  simulator was up, or the disk filled. Check `xcrun simctl list devices
  booted` and `df -h`.
- **A task failed before any test executed.** The grader retries a run whose
  app would not install or whose test runner never attached, and records a
  warning when it does. Two in a row is the host, not the model.
- **A verdict looks wrong.** Every number traces to a run directory under
  `.applebench/runs/`: `result.json` for the verdict, `events.jsonl` for the
  trajectory, `logs/` for the build and test output, `diff.patch` for exactly
  what the agent changed.
