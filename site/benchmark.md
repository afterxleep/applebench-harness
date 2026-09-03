---
title: The benchmark
permalink: /benchmark/
lede: >-
  What AppleBench contains, how a task is built, and what a passing result
  actually proves.
description: >-
  The AppleBench task set: eight categories of operational Apple-platform work,
  graded independently after the agent exits.
---

## The question

**Can an AI coding agent take an Apple-development task from request to
verified working result, without a human stepping in?**

That is the whole benchmark. Not "did it produce a plausible diff", but did the
app build, did the tests pass, did it launch on a simulator and survive, does
the project configuration actually resolve the way it claims to.

## The shape of the set

134 scoring tasks across eight categories. Each one is a small, self-contained Xcode
project with a single planted defect, and a prompt that states the **symptom**
and never the cause or the file. The diagnosis is the task.

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

Language-level Swift and concurrency were deliberately removed. Other
benchmarks cover them well and overlap buys nothing. What nobody else
measures is whether an agent can drive the Apple toolchain.

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
no composite score.

## The graders

| Grader | What it proves |
|---|---|
| `build` | Fresh `xcodebuild build` with clean derived data succeeds |
| `xctest` | Fresh `xcodebuild test` passes; totals parsed from the `.xcresult` bundle, not scraped from terminal output. Zero executed tests is a FAIL |
| `xcuitest` | Same contract, for UI test bundles, on the run's dedicated simulator |
| `runtime` | The app builds, installs, launches, and survives an observation window; a screenshot is captured as evidence |
| `file` | Deterministic assertions about the final workspace: existence, contents, regex, whether the diff touched a path |
| `xcodeproj` | Project configuration as it *resolves*, never as `project.pbxproj` text |

The `xcodeproj` grader is the one worth dwelling on. Build settings are
answered by `xcodebuild -showBuildSettings -json`; `Info.plist` keys and bundle
contents are read out of the **built product**. Nothing reads the project
file's text, so a plausible-looking line pasted into `project.pbxproj` that
does not actually take effect cannot pass.

## Are the tasks sound?

A benchmark result only means something if the task is genuinely broken and
genuinely solvable. Two in-process agents establish both halves before a task
ships:

- **`fake`** changes nothing, so a sound task must **FAIL**.
- **`solution`** applies the fixture's reference patch, so a sound task must
  **PASS**.

```text
Task                   fake       solution   Verdict
----------------------------------------------------------------
runtime-002            FAIL       PASS       ok
build-002              FAIL       PASS       ok
```

The reference patch lives outside every checkout, so a real agent working in
the workspace never sees it. `solution` is never reported as a benchmark
result; it exists only to prove the other half of the contract.

## Public harness, private answers

The set is partitioned:

- **`gold`**: 134 scoring tasks. Prompts, fixtures and expected outputs stay
  unpublished. Published scores come from this suite only.
- **`dev`**: a small leakable subset that ships with the open harness and is
  **never scored**.

These defend against different threats. Keeping the answers off the internet
is the only thing that stops pretraining contamination, the slow leak
measured in months. It does nothing about an agent that searches mid-run, so
scoring runs are sandboxed too: the agent runs in a VM that default-denies
every network destination and mounts only its workspace, leaving the standard
Apple toolchain and nothing else. Each run records whether it was isolated
that way.

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
- **No composite score, leaderboard, or significance testing.** The harness
  emits raw per-run variables and stops there. Weighting eight categories into
  one number is a claim about what matters, and that claim belongs to whoever
  is asking the question, not to the benchmark.
