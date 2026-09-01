# AppleBench

Can an AI coding agent take an Apple-development task from request to a
verified working result, without a human stepping in?

AppleBench hands an agent an isolated checkout of a real Xcode project with
something genuinely wrong in it, records everything the agent does, and then,
once the agent has exited, grades the workspace it left behind with fresh
`xcodebuild`, XCTest, XCUITest, resolved build settings and the app running on
a simulator.

Agents do not grade themselves.

## What is in this repository

Everything needed to run the benchmark: the grading engine, the task schema,
the fixture tooling, the isolation model, and eight sample tasks with their
fixtures. The samples are real tasks, not toys. They are meant to be read,
run, and copied from when writing your own.

They are never used for published scores. Those come from a separate,
private task set, because a benchmark whose answers are on the internet stops
measuring anything the moment somebody scrapes it.

Keeping answers closed and sealing the run solve two different problems, so
a scoring run is sandboxed: `--vm` puts the agent in a VM that default-denies
every network destination and mounts nothing of the host but the workspace,
with the standard Apple toolchain and nothing else. Run without it and the
agent's web tools are off but its process is not confined, which is fine for
development and is not a number to publish. Each run records which of the two
it was.

## Requirements

| | |
|---|---|
| macOS | Apple Silicon |
| Xcode | 16 or later |
| Simulator runtime | iOS 26.5 with an `iPhone 17` device type, or override it below |
| XcodeGen | `brew install xcodegen` |

No task pins an Xcode version. What every task names is a simulator, and that
is the only thing tying the set to a recent Xcode. To run against a runtime
your Xcode already has:

```bash
export APPLEBENCH_SIMULATOR_DEVICE="iPhone 16"
export APPLEBENCH_SIMULATOR_RUNTIME="iOS 18.5"
```

## Bring your own tasks

A fresh clone runs on the bundled samples with no arguments. Point at any
other task set with `APPLEBENCH_TASKSET`:

```bash
export APPLEBENCH_TASKSET=/path/to/your/tasks
```

A task set is any directory laid out like the one here:

```text
<taskset>/Examples/Tasks/*.yaml     one file per task
<taskset>/Examples/Suites/*.yaml    named lists of task ids
<taskset>/Fixtures/<Name>/          the app each task is set in
```

That is how the private scoring set is run, and how you would run your own:
clone this harness, point it at a task set, and nothing about those tasks
ever lands in this repository.

## Try it

```bash
swift build
./Scripts/prepare-fixtures.sh

# An agent that changes nothing. A sound task must FAIL.
swift run applebench run runtime-002 --agent fake

# The reference fix. The same task must now PASS.
swift run applebench run runtime-002 --agent solution

# A real model. The agent is OpenCode and any model it can reach works,
# so an OpenRouter id is passed straight through.
swift run applebench run runtime-002 --model anthropic/claude-sonnet-5
swift run applebench run runtime-002 --model openrouter/minimax/minimax-m3

# A whole suite, with the wrapper CLIs hidden so the agent has to drive the
# raw toolchain
./Scripts/run-benchmark.sh --suite dev --model openrouter/minimax/minimax-m3 \
  --allow-env OPENROUTER_API_KEY --strip-wrapper-clis
```

Those two agents are the contract every task has to satisfy before it earns a
place in the set: fail for an agent that changes nothing, pass once the
reference fix is applied. A task that passes unfixed hands out free marks. A
task that fails when correctly fixed takes them away regardless of what the
model did. Neither measures anything.

```bash
./Scripts/verify-fixtures.sh      # assert both halves, for every task here
```

## Reading a result

Every run writes `result.json` for the verdict, `events.jsonl` for the full
trajectory, `logs/` for the build and test output, and `diff.patch` for
exactly what the agent changed. Every number traces back to one of those.

Token counts and cost come from the agent CLI and stay `null` when it did not
report them. Never zero, never estimated.

## Documentation

- [`docs/RUNNING.md`](docs/RUNNING.md): running a suite end to end, and how to isolate the agent
- [`docs/AUTHORING.md`](docs/AUTHORING.md): the task schema and fixture layout
- [`docs/GRADING.md`](docs/GRADING.md): what each grader asserts and how a verdict is reached
- [`docs/AGENTS.md`](docs/AGENTS.md): the agent adapters and what each one controls
- [`docs/RESULTS.md`](docs/RESULTS.md): the run artifacts and the exported schema
- [`docs/TESTING.md`](docs/TESTING.md): how the harness itself is tested
- [`docs/SAFETY.md`](docs/SAFETY.md): run limits and what is enforced
- [`docs/READINESS.md`](docs/READINESS.md): what has been verified, and on what
- [`docs/PUBLIC.md`](docs/PUBLIC.md): what is open, what is closed, and why

## Licence

MIT.

Not affiliated with, endorsed by, sponsored by, or funded by Apple Inc.
Apple, Xcode, Swift, SwiftUI, iOS and macOS are trademarks of Apple Inc.,
used here only to say what is being tested.
