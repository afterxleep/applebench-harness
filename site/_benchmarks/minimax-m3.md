---
title: "minimax/MiniMax-M3, Gold Suite 1.2, 110/148 passed"
date: 2026-09-07
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: minimax-m3
model: "minimax/MiniMax-M3"
harness: "opencode, opencode 1.18.27, opencode 1.18.30"
tasks: 148
passed: 110
description: >-
  AppleBench results for minimax/MiniMax-M3 on Gold Suite 1.2:
  110 of 148 tasks completed to a verified result (74.3% pass rate),
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

## September 10 composition expansion

MiniMax M3 completed none of the five composition tasks. Three reached the old
wall-clock cap, while two completed with invalid workspaces. No result was
rerun.

## Missing cost telemetry

Eight tasks have no complete list-price telemetry: `ops-010`, `ops-012`,
`ops-018`, `ops-024`, `project-004`, `storekit-001`, `ui-auto-003`, and
`visual-004`. The reported suite cost excludes those attempts rather than
treating them as free, while their pass/fail outcomes remain in the pass rate.
