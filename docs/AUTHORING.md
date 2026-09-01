# Writing tasks and fixtures

## Writing a task

```yaml
id: runtime-002
title: Profile screen crashes before its data arrives
category: runtime        # build | tests | runtime | visual | interaction | project | frameworks | ops
difficulty: 2            # 1...10, comparative within the category
tags: [crash, async, swiftui]   # free-form labels; no structural meaning

repository:
  url: ./.applebench/fixtures/AsyncLoadFixture
  commit: HEAD

prompt: |
  The app dies as soon as the profile screen appears.
  Fix it so the screen comes up and shows the profile once it has loaded.

environment:
  xcode: "27.0"          # optional; strict match when present
  platform: ios
  simulator:
    device: "iPhone 17"
    runtime: "iOS 26.5"

limits:
  timeout_seconds: 900   # enforced by AppleBench, not the agent
  max_cost_usd: 5        # advisory; honored by adapters that support it
  max_tokens: 100000

graders:
  - type: build
    project: AsyncLoadFixture.xcodeproj
    scheme: AsyncLoadFixture

  - type: xcuitest
    project: AsyncLoadFixture.xcodeproj
    scheme: AsyncLoadFixture
    tests:
      - AsyncLoadFixtureUITests/ProfileLoadTests/testProfileAppearsAfterLoading

  - type: runtime
    project: AsyncLoadFixture.xcodeproj
    scheme: AsyncLoadFixture
    launch:
      bundle_identifier: com.applebench.AsyncLoadFixture
    must_not_crash: true
```

`category` and `difficulty` describe where a task sits in the set;
`difficulty` outside 1...10 is rejected at load time. `tags` is free-form
labelling only.

A task passes only if **all** its graders pass; the primary metric is
`completed tasks / attempted tasks`. There is no composite score.

Prompts state the **symptom**, never the cause or the file, the diagnosis is
the task.

### Grader types

- **`build`**, fresh `xcodebuild build` with clean derived data.
- **`xctest`**, fresh `xcodebuild test`; supports `test_plan`, `tests`
  (`-only-testing:`), `skip_tests`; totals parsed from the `.xcresult` bundle,
  not scraped from terminal output. Zero executed tests is a FAIL.
- **`xcuitest`**, same contract, for UI test bundles, against the run's
  dedicated simulator.
- **`file`**, deterministic assertions: `exists`, `contains`, `matches`
  (regex), `changed` (diff includes/excludes path).
- **`runtime`**, builds, installs, and launches the app on the benchmark
  simulator, verifies the process survives `observation_seconds`, and captures
  a final screenshot as evidence.
- **`xcodeproj`**, project configuration as it *resolves*, never as
  `project.pbxproj` text.

#### The `xcodeproj` grader

```yaml
- type: xcodeproj
  project: TargetMembershipFixture.xcodeproj
  scheme: TargetMembershipFixture
  build_settings:                   # from xcodebuild -showBuildSettings -json
    - key: IPHONEOS_DEPLOYMENT_TARGET
      equals: "18.0"
    - key: SWIFT_VERSION
      matches: "^6"
  info_plist:                       # the BUILT product's Info.plist
    - key: NSCameraUsageDescription
      exists: true
  bundle_contains:                  # paths inside the built .app
    - Assets.car
```

`build_settings` are answered by `xcodebuild -showBuildSettings -json`, parsed
as JSON. `info_plist` and `bundle_contains` build the scheme into the run's
fresh derived data and read the product bundle at `BUILT_PRODUCTS_DIR` /
`FULL_PRODUCT_NAME`. Nothing reads the project file's text, so a plausible-
looking line pasted into `project.pbxproj` that does not actually take effect
cannot pass. Everything else about project configuration, target membership,
scheme test wiring, package linkage, is graded by consequence, through the
build, test, or runtime grader.

### Hidden evaluation

Task prompts and graders are not welded together. A task file may omit
`graders`, with the evaluation supplied separately at run time, so benchmark
maintainers can distribute public prompts and keep verification private:

```bash
applebench run tasks/navigation-001/task.yaml \
  --evaluation evaluators/navigation-001/evaluation.yaml \
  --model anthropic/claude-sonnet-5
```

See `Examples/SplitTasks/` and `Examples/Evaluations/` for the layout.


## Fixtures

Every task owns one fixture in `Fixtures/`, a small, self-contained app with a
single planted defect. A fixture is:

```text
Fixtures/<Name>/
  project.yml            XcodeGen spec              (stripped from the snapshot)
  project.solution.yml   fixed spec, when the       (stripped from the snapshot)
                         defect lives in the project
  Sources/               the app
  UITests/ | Tests/      the graded tests        (withheld, see below)
  Design/                design spec, for visual tasks
  README.md              documents the planted defect (stripped)
  .solution/             the authored fix, as an overlay (stripped)
  solution.patch         generated from .solution/   (stripped)
```

`./Scripts/prepare-fixtures.sh` snapshots each fixture into a standalone local
git repository under `.applebench/fixtures/`, generating the Xcode project with
XcodeGen and **stripping every authoring file**, `project*.yml`, `README.md`,
`.solution/`, and `solution.patch`, so the agent receives a normal repository
with no trace of how it will be graded or what the answer is. Each fixture's
patch is copied to `.applebench/solutions/<Name>.patch`, outside every checkout.

### Withholding the graded tests

An agent that can read the assertions is not diagnosing anything; the test file
names and class names alone give most of it away. So the tests are withheld
too, and the agent receives an app with **no test target at all**.

`prepare-fixtures.sh` copies the fixture's spec, its tests, and the generated
project into `.applebench/verification/<Name>/`, then regenerates the project
the agent receives from a spec with every test target removed
(`Scripts/make-agent-spec.py`). After the agent's process has exited and its
diff has been captured, the runner overlays that directory back onto the
workspace and regenerates the project from the spec, so files the agent added
are picked up rather than dropped. The run records a
`verification_materialised` event naming exactly what was overlaid.

Two consequences worth knowing:

- The agent cannot run the graded tests to check itself. It can still build,
  run the app, and write tests of its own. The diagnosis has to come from the
  symptom, which is the task.
- Grading an isolated fixture needs XcodeGen on the grading host.

Withholding is the default and is derived from the task set by
`Scripts/fixture-isolation.py`, not kept as a list. It is **off** for fixtures
where a task legitimately needs the agent to change the project or to author
its own test target, `project`, `ops` and `interaction` tasks, and anything
carrying a `project.solution.yml`. Overlaying a project onto that work would
discard the answer, so those fixtures keep their tests in the checkout and are
graded on the built product or on the tests the agent writes.

### The fixture self-check

A benchmark result only means something if the fixture is genuinely broken and
genuinely solvable. Two in-process agents establish that:

- **`fake`** changes nothing, a sound fixture must **FAIL**.
- **`solution`** applies `.applebench/solutions/<Name>.patch` and exits, a
  sound fixture must **PASS**.

```bash
./Scripts/verify-fixtures.sh                    # every task
./Scripts/verify-tasks.sh runtime-002 visual-002   # a named subset
```

Both run the same engine. Each run is bounded, the per-run simulator is
deleted afterwards, and a second run refuses to start while another is in
flight: an interrupted run leaves its simulator booted, and a stray booted
simulator makes the next `xcodebuild test` hang against its own device rather
than return a verdict.

A run that dies before any test can execute, the app failed to install, the
runner never attached, is retried once. That is the host having a bad moment
after a long series of UI runs, and recording it as the agent's failure turns
a score into a coin flip.

```text
Task                   fake       solution   Verdict
----------------------------------------------------------------
runtime-002          FAIL       PASS       ok
build-002              FAIL       PASS       ok
```

The script exits non-zero on any deviation, and distinguishes a legitimate FAIL
from a run that could not execute at all. `solution` is never a benchmark
result; it exists only to prove the other half of the contract.

`./Scripts/make-solutions.sh` regenerates each `solution.patch` from its
`.solution/` overlay by materializing the fixture twice, broken and fixed, through exactly the prepare-fixtures pipeline and diffing the results. That is
what lets a `project`-category patch modify the *generated* `.xcodeproj`, which
is where the defect actually lives once the snapshot is built.

### Retired

The two algorithm tasks and the five toolchain-operations tasks were retired,
along with their three fixtures. Complexity-class puzzles are not
Apple-platform engineering, and the toolchain-operations tasks measured whether
an agent would *save a log file*, which the operational tasks now cover as a
means rather than as an end. All of it remains in git history.

