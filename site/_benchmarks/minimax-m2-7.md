---
title: "minimax/MiniMax-M2.7, gold suite, 861 points"
date: 2026-09-06
suite: gold
suite_revision: "2026-09-09"
score_spec: "points-v2"
attempt: "latest"
data: minimax-m2-7
model: "minimax/MiniMax-M2.7"
harness: "opencode, opencode 1.18.27, opencode 1.18.30"
tasks: 143
passed: 89
points: 861
points_available: 1430
description: >-
  AppleBench results for minimax/MiniMax-M2.7 on the gold suite:
  861 of 1430 points and 89 of 143 tasks completed to a
  verified result, with per-category points, cost against wall-clock time,
  and every task.
---
## Conditions

| | |
|---|---|
| Attempt rule | Latest per task. |
| Reasoning | Provider default. This model exposes no selectable effort level. |
| Isolation | Sandboxed. Reference solutions, task files and other runs are unreadable; writes are confined to the workspace; execution is limited to Apple's toolchain and third-party wrappers are denied. Web tools off, hermetic config, host egress open. |

## September 8 concurrency expansion

The suite adds six expert Swift concurrency tasks. MiniMax M2.7 completed the
actor-reentrancy task and failed the continuation, task-group, shared-lifetime,
multicast-stream and isolated-conformance tasks, finishing the addition 1/6.

## September 9 calibration

The recorded UI trees for `g2-locale-004` show correct English and German
dates, so its former false failure is corrected without rerunning the model.
The materially revised `ui-auto-014` task was rerun: M2.7 changed the app and
test, but used a nonexistent `XCUIApplication.keyboard` API, so the UI test
target did not compile. The retry reproduced the compiler error and the failure
is retained. The 143rd task, `g2-visual-001`, was run at provider-default
reasoning: M2.7 fixed the Arabic layout but moved the reply counts outside the
window in English, so the model failure is retained.

## Excluded from the score

| | |
|---|---|
| Public sample tasks | `build-002`, `ops-004`, `project-001`, `runtime-002`, `tests-003`, `visual-002`. They ship with the open harness and are never scored. |
