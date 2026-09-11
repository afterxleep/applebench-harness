---
title: The benchmark
permalink: /benchmark/
kicker: AppleBench / The benchmark
lede: >-
  What Gold Suite 1.2 contains, how a task is validated, and what a passing
  result actually proves.
description: >-
  The AppleBench task set: eight categories of operational Apple-platform work,
  graded independently after the agent exits.
---

{% assign current_suite = site.data.suite_revisions | where: "current", true | first %}
{% assign scoring_tasks = current_suite.gold_tasks %}
{% assign sample_tasks = current_suite.public_sample_tasks %}
{% assign category_count = current_suite.category_tasks | size %}

<nav class="article-index" aria-label="On this page">
  <p>On this page</p>
  <ol>
    <li><a href="#the-question">The question</a></li>
    <li><a href="#the-shape-of-the-set">Shape of the set</a></li>
    <li><a href="#what-a-task-looks-like">A task, in full</a></li>
    <li><a href="#the-graders">The graders</a></li>
    <li><a href="#are-the-tasks-sound">Task calibration</a></li>
    <li><a href="#public-harness-private-answers">Public and private</a></li>
    <li><a href="#what-is-deliberately-absent">Deliberate limits</a></li>
  </ol>
</nav>

## The question

**Can an AI coding agent take an Apple-development task from request to
verified working result, without a human stepping in?**

That is the whole benchmark. Not "did it produce a plausible diff", but did the
app build, did the tests pass, did it launch on a simulator and survive, does
the project configuration actually resolve the way it claims to.

## The shape of the set

**{{ current_suite.name }}** contains {{ scoring_tasks }} tasks across
{{ category_count }} categories. Each one is a small,
self-contained Xcode project with a planted defect. The prompt describes the
**symptom**, but does not reveal the cause or the file. Finding the cause is
part of the task.

| Category | What it tests |
|---|---|
| `build` | Xcode/compiler failures that are Apple-SDK specific (availability, linking) |
| `tests` | Diagnose → fix → rerun against existing tests |
| `runtime` | Problems invisible at compile time |
| `visual` | Reading a design spec and fixing layout |
| `interaction` | Running the app and writing XCUITests |
| `project` | Target membership, Info.plist, assets, schemes, SPM |
| `frameworks` | SwiftData, Core Data, WidgetKit, App Intents |
| `ops` | Raw `xcodebuild` / `simctl` / `devicectl` operational loops |

Difficulty runs 1 to 10 and is **comparative within a category**, not an absolute
scale across the set. A `visual` 5 and an `ops` 5 are not the same amount of
work; they are each the middle of their own ladder.

The suite now includes expert Swift concurrency problems when they can be
checked with deterministic builds and tests. The main focus remains the full
Apple-development workflow: diagnose, edit, build, test, launch, and verify.

## What a task looks like

This one ships with the open harness, so it is safe to show in full.

```yaml
id: runtime-002
title: Profile screen crashes before its data arrives
category: runtime
difficulty: 2
tags: [crash, async, swiftui]

repository:
  url: ./.applebench/fixtures/AsyncLoadFixture
  commit: HEAD

prompt: |
  The app dies as soon as the profile screen appears.
  Fix it so the screen comes up and shows the profile once it has loaded.

environment:
  platform: ios
  simulator:
    device: "iPhone 17"
    runtime: "iOS 26.5"

limits:
  timeout_seconds: 900

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
    observation_seconds: 8
```

The prompt says the app dies and nothing else. It does not say why, or which
file to open. Working that out is the task.

A task passes only if **every** grader passes. There is no partial credit and
no composite rating.

## The graders

| Grader | What it proves |
|---|---|
| `build` | Fresh `xcodebuild build` with clean derived data succeeds |
| `xctest` | Fresh `xcodebuild test` passes; totals parsed from the `.xcresult` bundle, not scraped from terminal output. Zero executed tests is a FAIL |
| `xcuitest` | Same contract, for UI test bundles, on the run's dedicated simulator |
| `runtime` | The app builds, installs, launches, and survives an observation window; a screenshot is captured as evidence |
| `uiflow` | The simulator is placed into a declared language, appearance, orientation, accessibility, permission, or lifecycle state; the app is driven and its accessibility tree or rendered state is checked |
| `file` | Deterministic assertions about the final workspace: existence, contents, regex, whether the diff touched a path |
| `xcodeproj` | Project configuration as it *resolves*, never as `project.pbxproj` text |
| `mutation` | An agent-authored test first passes, then fails after the grader deliberately breaks the behavior it claims to cover |
| `trajectory` | Harness-owned events prove an operational deliverable was produced by the required work rather than merely asserted in a report |

The `xcodeproj` grader is the one worth dwelling on. Build settings are
answered by `xcodebuild -showBuildSettings -json`; `Info.plist` keys and bundle
contents are read out of the **built product**. Nothing reads the project
file's text, so a plausible-looking line pasted into `project.pbxproj` that
does not actually take effect cannot pass.

## Are the tasks sound?

A benchmark result only means something if the task is genuinely broken and
genuinely solvable. Two controlled harness adapters establish both halves
before a task ships:

- **`fake`** changes nothing, so a sound task must **FAIL**.
- **`solution`** applies the fixture's reference patch, so a sound task must
  **PASS**.

```text
Task                   fake       solution   Verdict
----------------------------------------------------------------
runtime-002            FAIL       PASS       ok
build-002              FAIL       PASS       ok
```

The reference patch lives outside every agent checkout, so a measured model
never sees it. `solution` is never reported as a benchmark result; it exists
only to prove the other half of the contract. The suite gate also rejects
comments that disclose the planted defect and confirms that isolated fixture
snapshots contain neither graded tests nor test targets.

## Public harness, private answers

The set is partitioned:

- **`gold`**: {{ current_suite.name }}, with {{ scoring_tasks }} measured tasks.
  Prompts, fixtures, private assertions, and reference repairs stay unpublished.
  Published pass rates come from this suite only.
- **`dev`**: {{ sample_tasks }} sample tasks that ship with the open harness and are
  **never included in published measurements**.

These defend against different threats. Keeping the answers off the internet
limits pretraining contamination, the slow leak measured in months. It does
nothing about an agent searching the host mid-run, so Gold Suite 1.2 also uses
a macOS sandbox. The agent can write only its workspace and cannot read task
files, reference solutions, graders, cached fixtures, or other runs. Web tools
are disabled, but a local run still permits the provider connection needed to
reach the model. The optional Tart VM mode adds host separation and
default-deny network egress. Each run records which isolation mode and network
policy it used.

For fixtures with withheld tests, those tests do not exist anywhere in the
agent-visible harness state. Only after the agent process exits does the runner
fetch the exact task-set commit into a unique temporary checkout, copy the
fixture's test material into the grading workspace, regenerate the project,
and delete the temporary checkout.

Neither substitutes for the other, and both have a shelf life. Rotation is the
actual long-term defense: fixtures are XcodeGen manifests with templated
defects, so the private set can be re-seeded periodically and a leaked
transcript stops being a valid key.

## What is deliberately absent

- **No pixel-diff or snapshot grading.** Visual tasks are decided by
  structural XCUITest assertions: label text, element order, hittability,
  frame geometry within the window.
- **No entitlement or capability tasks.** Fixtures build with
  `CODE_SIGNING_ALLOWED = NO`, so entitlements cannot be honestly verified,
  and a grader that cannot honestly verify something should not exist.
- **No composite rating or significance claim.** The results page orders models
  by pass rate and shows list-price cost and active time beside it. Those
  measurements are not blended into a synthetic rating.
