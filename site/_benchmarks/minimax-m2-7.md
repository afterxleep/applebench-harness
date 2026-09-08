---
title: "minimax/MiniMax-M2.7, gold suite, 861 points"
date: 2026-09-06
suite: gold
suite_revision: "2026-09-08"
score_spec: "points-v2"
attempt: "latest"
data: minimax-m2-7
model: "minimax/MiniMax-M2.7"
harness: "opencode, opencode 1.18.27"
tasks: 142
passed: 89
points: 861
points_available: 1420
description: >-
  AppleBench results for minimax/MiniMax-M2.7 on the gold suite:
  861 of 1420 points and 89 of 142 tasks completed to a
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

## Excluded from the score

| | |
|---|---|
| Public sample tasks | `build-002`, `ops-004`, `project-001`, `runtime-002`, `tests-003`, `visual-002`. They ship with the open harness and are never scored. |
