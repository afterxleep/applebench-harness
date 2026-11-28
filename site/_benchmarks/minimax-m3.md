---
title: "MiniMax M3, Gold Suite 1.3, 142/178 passed"
date: 2026-11-26
suite: gold
suite_revision: "2026-11-28"
attempt: "latest"
data: minimax-m3
model: "minimax/MiniMax-M3, minimax/minimax-m3"
harness: "opencode, opencode 1.18.27, opencode 1.18.30, opencode 1.18.31, opencode 2.3.0, opencode 2.3.2"
tasks: 178
passed: 142
description: >-
  AppleBench results for MiniMax M3 on Gold Suite 1.3:
  142 of 178 tasks completed to a verified result (79.8% pass rate),
  with cost, active time, per-category results,
  and every task.
---
**28 November 2026: Gold Suite 1.3.** Thirty framework tasks for the iOS 27 SDK join the suite, 178 tasks in all. 17 of 30 passed. foundationmodels-001 (14 November) is now a pass: it had been failed for a refused search of the harness and for fetching public Apple documentation, and neither voids a run any more (outside network is blocked instead). datadetection-001 had passed only because its tests' date was still in the future on the device clock; after the tests were corrected it was run again and failed (it never reads the year from the message's date). Through OpenRouter at the provider default. A few of the new tasks were corrected after review (a fixed date in two hidden tests, an over-strict test in two more, the simulator to use in every prompt), every model's earlier runs of them were graded again against the corrected tests, and a run that no longer passed was run again.

**26 November 2026.** Sixteen bug-fix tasks (interaction-001 to -004, runtime-001, tests-001, -002, -005, visual-001, -003, -004, -005, activitykit-001, healthkit-001, push-002, storekit-001) now withhold their graded tests from the agent: they are absent from its checkout and the harness's copy is overlaid at grading. Every model is re-run on them and the re-runs replace the earlier results. M3's sixteen re-runs are in, through OpenRouter (`openrouter/minimax/minimax-m3`): 11 passed. In interaction-003 the agent tried to list the task-set checkout for hints; the sandbox refused it, nothing came back, and the run is scored on its graders (a pass). Fair fails: tests-005, healthkit-001, push-002 and storekit-001. Four attempts that OpenRouter rate limits ended before any work were run again; the retries are what count.

**28 November 2026.** An audit of every recorded run found that M3's widget-002 run from 7 September read the task's graded test before making its change; the harness folder was not yet sealed from agents then. Reading protected material voids a run, so that pass is now a fail: 125 of 148.

## Conditions

| | |
|---|---|
| Attempt rule | Latest per task. |
| Reasoning | Provider default. This model exposes no selectable effort level. |
| Isolation | Sandboxed. Reference solutions, task files and other runs are unreadable; writes are confined to the workspace; execution is limited to Apple's toolchain and third-party wrappers are denied. Web tools off, hermetic config, host egress open. |

## September 8 concurrency expansion

The suite adds six expert Swift concurrency tasks. MiniMax M3 completed the
actor-reentrancy, continuation, task-group and multicast-stream tasks. It
failed the shared-lifetime and isolated-conformance tasks, finishing the
addition 4/6.

## September 9 calibration

`g2-locale-004` is corrected from fail to pass from its saved localized UI
trees. M3's saved `g2-lifecycle-002` patch was replayed without another model
call and passed both isolated flows. The materially revised `ui-auto-014` task
was rerun and passed build, its UI test, the explicit keyboard-disappearance
check, and mutation grading. On the new `g2-visual-001` task, M3 used a
different implementation from the reference solution and passed the English,
Arabic, and file graders under provider-default reasoning.

## Coverage notes

| | |
|---|---|
| Public sample tasks | `build-002`, `ops-004`, `project-001`, `runtime-002`, `tests-003`, `visual-002`. They ship with the open harness and are not included in published measurements. |

## September 10 end-to-end expansion

MiniMax M3 completed none of the five end-to-end tasks. Three reached the old
wall-clock cap, while two completed with invalid workspaces. No result was
rerun.

## Missing cost telemetry

Eight tasks have no complete list-price telemetry: `ops-010`, `ops-012`,
`ops-018`, `ops-024`, `project-004`, `storekit-001`, `ui-auto-003`, and
`visual-004`. The reported suite cost excludes those attempts rather than
treating them as free, while their pass/fail outcomes remain in the pass rate.

## November 17 review

A review of every recorded run found that two of M3's September passes had reached
material outside their workspace: `ops-015` read a file in the harness checkout and
`ops-023` listed a harness directory, at a time when the sandbox did not deny those
paths. Any such access fails a run, so both were run again under the current sandbox,
through OpenRouter (`openrouter/minimax/minimax-m3`, OpenCode 2.3.0) because the
original direct MiniMax route is no longer available on this host. `ops-023` passed;
`ops-015` failed, which moves the total from 129 to 128.

The same review found that `ops-025` had passed by installing a Python imaging package from
the internet to build its deliverable. Runs may not reach the network, so it was run again
under the current harness, which allows no outside connection except to the model provider.
It passed again, building the image with a script of its own. The other 145 results are the
original direct-API runs.
