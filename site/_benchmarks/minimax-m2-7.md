---
title: "minimax/MiniMax-M2.7, gold suite, 3681 points"
date: 2026-09-02
suite: gold
suite_revision: "2026-08-31"
score_spec: "points-v1"
attempt: "first"
data: minimax-m2-7
model: "minimax/MiniMax-M2.7"
harness: "opencode 1.18.25"
tasks: 134
passed: 80
points: 3681
points_available: 6840
description: >-
  AppleBench results for minimax/MiniMax-M2.7 on the gold suite:
  3681 of 6840 points and 80 of 134 tasks completed to a
  verified result, with per-category points, cost against wall-clock time,
  and every task.
lede: >-
  The previous MiniMax generation on the same suite, published for the
  comparison it makes possible: 55.2% of the points against M3's 72.5%, on the
  same 123 tasks, the same harness and the same host.
---
## Which attempt counts

**The first attempt per task**, the same rule as the M3 run on this page's
sibling, so the two are read the same way.

## What the comparison is worth

Both models ran the same suite through the same harness on the same host, so
the difference is the model.

|            | M2.7  | M3    |
|------------|-------|-------|
| Points     | 55.2% | 72.5% |
| Pass rate  | 61.0% | 82.9% |

Read the two rows together. M2.7 passes 61% of its tasks and earns 55.2% of
its points, so the tasks it does solve, it solves expensively. That gap is the
case for scoring in points at all: a pass rate counts the ticks, and the points
also count what each tick cost.

## Isolation

Not sandboxed. The agent's web tools were off and its configuration replaced
with a hermetic one, but the process was not confined to a VM and host egress
was open. A development-grade number, not a sealed one.
