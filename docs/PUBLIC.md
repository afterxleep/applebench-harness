# Open harness, closed scoring set

AppleBench is one public harness plus a task set you point it at. The split is
what keeps a published score meaning something.

## The harness is open

Everything in this repository: the grading engine, the task schema, the fixture
tooling, the isolation model, the graders (`build`, `xctest`, `xcuitest`,
`runtime`, `file`, `xcodeproj`), and eight sample tasks with their fixtures.

Read it, run it, disagree with it. That is the point of it being here.

## The scoring tasks are not

Published scores come from a separate, private task set: prompts, fixtures and
expected outputs that are not on the internet. A benchmark whose answers are
public stops measuring anything the moment somebody scrapes it, and no amount
of sandboxing fixes a model that already saw the fix during pretraining.

Keeping answers closed and sealing the run are two different defenses, and both
are required. Runs are sandboxed either way: no internet, no search, the
standard Apple toolchain and nothing else.

## Pointing the harness at a task set

`APPLEBENCH_TASKSET` is the only wiring. With nothing set the harness runs the
bundled samples, so a fresh clone works with no arguments.

```bash
export APPLEBENCH_TASKSET=/path/to/task-set
./Scripts/prepare-fixtures.sh
./Scripts/run-benchmark.sh --suite gold --agent <agent> --model <model>
```

A task set is a directory holding exactly three things:

```
Examples/Tasks/     one YAML per task
Examples/Suites/    gold.yaml or dev.yaml, plus any subsets
Fixtures/           one Xcode project per fixture, with its .solution overlay
```

Nothing is copied in either direction. Prepared fixtures, solutions, run
artifacts and reports are all written under the harness clone's `.applebench/`,
so the task set stays clean and a closed one never lands in a public checkout.

## Which suite a score may come from

`gold.yaml` marks a scoring set: everything in it is closed, and a published
number may only come from it. `dev.yaml` marks an open one, and nothing in it
is ever scored. A task set declares one or the other, never both, and
`./Scripts/check-task-set.sh` fails if a task belongs to neither.

## Writing your own

`docs/AUTHORING.md` covers the task schema and fixture layout, `docs/GRADING.md`
covers the graders. Start by copying a sample: each one is a single YAML file
plus a fixture directory with a `.solution` overlay.

Whatever you write has to hold the contract before it is worth running:

```bash
./Scripts/verify-tasks.sh <task-id>
```

`--agent fake`, which changes nothing, must FAIL. `--agent solution`, which
applies the reference fix, must PASS. A task that fails either way is measuring
your fixture, not the model.

## Rotation

Fixtures are XcodeGen manifests with templated defects, so a closed set can be
regenerated rather than retired. Keeping answers closed buys time against
contamination; rotating the set is what keeps the benchmark alive past the first
leak.
