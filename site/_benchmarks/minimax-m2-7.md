---
title: "minimax/MiniMax-M2.7, gold suite, 3657 points"
date: 2026-09-02
suite: gold
suite_revision: "2026-09-03"
score_spec: "points-v1"
attempt: "latest"
data: minimax-m2-7
model: "minimax/MiniMax-M2.7"
harness: "opencode 1.18.25"
tasks: 134
passed: 79
points: 3657
points_available: 6840
description: >-
  AppleBench results for minimax/MiniMax-M2.7 on the gold suite:
  3657 of 6840 points and 79 of 134 tasks completed to a
  verified result, with per-category points, cost against wall-clock time,
  and every task.
lede: >-
  The first run measured against the hardened suite: 134 tasks, including 11
  that require driving the device itself, and 25 rewritten so that a test which
  asserts nothing no longer passes. 53.5% of the points, 59.0% of the tasks.
---
## Which attempt counts

**The latest attempt per task.** Twenty-five of these tasks were rewritten
after this model first ran them, so the earlier attempt scored a version that
no longer exists; letting it win would credit the model with passes on tasks it
was never asked to solve. Where a task has not changed, there is only one
attempt to choose from.

## What changed under the model

Twenty-five previously-passed tasks were hardened against tests that pass
without asserting anything, and eleven tasks were added that need the device
driven — rotation, a language change, hardware buttons, list ordering,
accessibility sizing.

|                     | before | after |
|---------------------|--------|-------|
| The 25 hardened     | 11     | 10    |
| The 11 new tasks    | —      | 5     |

The hardened tasks moved by one, but that number is quieter than the data. Of
the 25, **seven flipped** — four to failing and three to passing — and nothing
was made easier, so three tasks going green on a harder version is variance
rather than improvement. A one-point delta on a single attempt per task is
inside the noise, and these results should be read as such until a model is run
more than once.

## What this is not comparable to

The M3 run on this page's sibling was measured on 123 tasks, before any of the
above. It is not a like-for-like comparison and the difference between the two
headline numbers is mostly the suite, not the model.

## Isolation

Not sandboxed. The agent's web tools were off and its configuration replaced
with a hermetic one, but the process was not confined to a VM and host egress
was open. A development-grade number, not a sealed one.
