---
title: "minimax/MiniMax-M3, gold suite, 878 points"
date: 2026-09-07
suite: gold
suite_revision: "2026-09-06"
score_spec: "points-v2"
attempt: "latest"
data: minimax-m3
model: "minimax/MiniMax-M3"
harness: "opencode, opencode 1.18.27"
tasks: 136
passed: 103
points: 878
points_available: 1360
description: >-
  AppleBench results for minimax/MiniMax-M3 on the gold suite:
  878 of 1360 points and 103 of 136 tasks completed to a
  verified result, with per-category points, cost against wall-clock time,
  and every task.
---
## Conditions

| | |
|---|---|
| Attempt rule | Latest per task. |
| Reasoning | Provider default. This model exposes no selectable effort level. |
| Isolation | Sandboxed. Reference solutions, task files and other runs are unreadable; writes are confined to the workspace; execution is limited to Apple's toolchain and third-party wrappers are denied. Web tools off, hermetic config, host egress open. |

## Excluded from the score

| | |
|---|---|
| Public sample tasks | `build-002`, `ops-004`, `project-001`, `runtime-002`, `tests-003`, `visual-002`. They ship with the open harness and are never scored. |

## Scored at the efficiency floor

`ops-010`, `project-004`, `ui-auto-003`, `ui-auto-014` and `visual-004` hit
the wall-clock limit and reported no token usage. All five workspaces graded
clean, so all five are passes at the 0.25 floor.
