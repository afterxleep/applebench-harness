---
title: "minimax/MiniMax-M2.7, Gold Suite 1.3, 91/173 passed"
date: 2026-09-06
suite: gold
suite_revision: "2026-09-11"
attempt: "latest"
data: minimax-m2-7
model: "minimax/MiniMax-M2.7"
harness: "opencode, opencode 1.18.27, opencode 1.18.30"
tasks: 173
passed: 91
description: >-
  AppleBench results for minimax/MiniMax-M2.7 on Gold Suite 1.3:
  91 of 173 tasks completed to a verified result (52.6% pass rate),
  with cost, active time, per-category results,
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

## Coverage notes

| | |
|---|---|
| Public sample tasks | `build-002`, `ops-004`, `project-001`, `runtime-002`, `tests-003`, `visual-002`. They ship with the open harness and are not included in published measurements. |
| `ops-027` | Rerun after Screen Recording permission was granted. The model produced a valid 5120×2880 PNG and passed both trajectory and file grading. |
| Cost coverage | `ops-003` is a failed task with no recoverable list-price telemetry, so the recorded suite-cost total excludes that attempt rather than treating it as free. |

## September 10 composition expansion

MiniMax M2.7 completed none of the five composition tasks. All five agents
finished before the old wall-clock cap; four left test targets that did not
compile and one left an app build failure. No result was rerun.

## September 11 pure Swift expansion

Gold Suite 1.3 adds 25 difficult pure Swift tasks with a 3,600-second allowance
per task. MiniMax M2.7 completed `swift-hard-007` and failed the other 24 tasks,
finishing the addition 1/25. Every result uses the latest recorded attempt.
