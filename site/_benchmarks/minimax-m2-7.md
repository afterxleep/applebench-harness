---
title: "MiniMax M2.7, Gold Suite 1.3, 104/178 passed"
date: 2026-11-26
suite: gold
suite_revision: "2026-11-28"
attempt: "latest"
data: minimax-m2-7
model: "minimax/MiniMax-M2.7, minimax/minimax-m2.7"
harness: "opencode 1.18.27, opencode 1.18.30, opencode 1.18.31, opencode 2.3.0, opencode 2.3.2"
tasks: 178
passed: 104
description: >-
  AppleBench results for MiniMax M2.7 on Gold Suite 1.3:
  104 of 178 tasks completed to a verified result (58.4% pass rate),
  with cost, active time, per-category results,
  and every task.
---
**28 November 2026: Gold Suite 1.3.** Thirty framework tasks for the iOS 27 SDK join the suite, 178 tasks in all. 3 of 30 passed. Its first attempt at the twenty 16 November tasks is not counted: OpenRouter credit ran out partway and the provider refused requests. They were run again; two runs that the credit limit still cut short were run once more. Through OpenRouter at the provider default. A few of the new tasks were corrected after review (a fixed date in two hidden tests, an over-strict test in two more, the simulator to use in every prompt), every model's earlier runs of them were graded again against the corrected tests, and a run that no longer passed was run again.

**26 November 2026.** Sixteen bug-fix tasks (interaction-001 to -004, runtime-001, tests-001, -002, -005, visual-001, -003, -004, -005, activitykit-001, healthkit-001, push-002, storekit-001) now withhold their graded tests from the agent: they are absent from its checkout and the harness's copy is overlaid at grading. Every model is re-run on them and the re-runs replace the earlier results. M2.7's sixteen re-runs are in, through OpenRouter (`openrouter/minimax/minimax-m2.7`): 10 passed. The rest of this report ran on MiniMax's own API.

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
| Cost coverage | Complete for all 148 tasks. The timed-out `ops-003` run was recovered from 215 usage events preserved identically in its event stream and raw agent log, then priced from the pinned model-owner rates used for every other task. |

## September 10 end-to-end expansion

MiniMax M2.7 completed none of the five end-to-end tasks. All five agents
finished before the old wall-clock cap; four left test targets that did not
compile and one left an app build failure. No result was rerun.
