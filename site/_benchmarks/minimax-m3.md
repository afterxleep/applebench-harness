---
title: "minimax/MiniMax-M3, gold suite, 4518 points"
date: 2026-09-02
suite: gold
suite_revision: "2026-09-03"
score_spec: "points-v1"
attempt: "latest"
data: minimax-m3
model: "minimax/MiniMax-M3"
harness: "opencode, opencode 1.18.25, opencode 1.18.27"
tasks: 134
passed: 103
points: 4518
points_available: 6840
description: >-
  AppleBench results for minimax/MiniMax-M3 on the gold suite:
  4518 of 6840 points and 103 of 134 tasks completed to a
  verified result, with per-category points, cost against wall-clock time,
  and every task.
---
## Conditions

| | |
|---|---|
| Attempt rule | Latest per task. |
| Reasoning | Provider default. This model exposes no selectable effort level. |
| Isolation | Not sandboxed. Web tools off, hermetic config, host egress open. |

## Excluded from the score

| | |
|---|---|
| Public sample tasks | `build-002`, `ops-004`, `project-001`, `tests-003`. They ship with the open harness and are never scored. |
| Launch failures | 8 runs under the model ids `minimax/minimax-m3` and `openrouter/minimax/minimax-m3`. Both mistyped; all 8 ended in under 5 seconds with no agent started. |

## Scored at the efficiency floor

`ops-010` and `ui-auto-005` hit the wall-clock limit and reported no token
usage. Both workspaces graded clean, so both are passes at the 0.25 floor.
