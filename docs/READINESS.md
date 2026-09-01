# Suite readiness

Recorded 2026-08-31, against the gold suite as it stands.

## The contract

A task earns its place by failing for an agent that changes nothing and
passing once the reference fix is applied. Anything else is not measuring the
model: a task that passes unfixed hands out free marks, and one that fails
even when fixed takes them away regardless of what the agent did.

```bash
./Scripts/prepare-fixtures.sh
./Scripts/verify-fixtures.sh
```

**123 of 123 gold tasks hold it.** Every category is covered: frameworks (50),
ops (29), ui-auto (19), interaction (5), and the build, tests, runtime,
visual and project families.

## What the agent is given

- Authoring files, `project*.yml`, `README.md`, `.solution/`,
  `solution.patch`, are stripped from every snapshot.
- No shipped source or test names the planted defect. Checked on every change
  by `check-fixture-leaks.sh`, in CI.
- For the 59 fixtures where no task requires the agent to change the project,
  the graded tests are withheld too: those snapshots carry **no test target at
  all**. The tests are overlaid after the agent's process has exited and its
  diff is captured, and the run records a `verification_materialised` event
  saying exactly what went in.

The reference solutions live in `.applebench/solutions/`, outside every
checkout. Proving a task is solvable does not make it easier.

## Running a sweep

Verification holds an atomic lock. Two sweeps at once means two booted
simulators, and `xcodebuild test` hangs against its own device when another
is up, the overlap then times out task after task and reads as a suite full
of broken fixtures. Each run is bounded, its simulator is deleted afterwards,
and its derived data is discarded once the verdict is recorded: a full sweep
is 246 runs, and keeping every build directory fills the disk, after which
everything remaining times out for no visible reason.

A run that dies before any test executes, the app failed to install, the
runner never attached, is retried once, and the retry writes its own result
bundle. That is the host having a bad moment; charging it to the agent turns
a score into a coin flip.

## Known gap

`visual-006` is **not** in the gold suite. Its three SwiftUI performance
defects are invisible to every grader here, XCUITest cannot time a `body`
invocation, so an agent that changes nothing passes it. Rather than score a
task that rewards inaction, or replace a false pass with a flaky timing
threshold, it sits in the unscored subset until there is a grader that can
observe render cost. The fixture is ready to use as it stands.
