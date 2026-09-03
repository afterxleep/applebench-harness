---
title: "minimax/MiniMax-M3, gold suite, 4304 points"
date: 2026-09-02
suite: gold
suite_revision: "2026-08-31"
score_spec: "points-v1"
attempt: "first"
data: minimax-m3
model: "minimax/MiniMax-M3"
harness: "opencode, opencode 1.18.25"
tasks: 123
passed: 102
points: 4304
points_available: 5940
description: >-
  AppleBench results for minimax/MiniMax-M3 on the gold suite:
  4304 of 5940 points and 102 of 123 tasks completed to a
  verified result, with per-category points, cost against wall-clock time,
  and every task.
lede: >-
  The first run scored in points. M3 passes four tasks in five and earns just
  under three quarters of the points available, and almost all of the shortfall
  that is not an outright failure comes from one family of tasks.
---
## Which attempt counts

**The first attempt per task**, over **the gold suite only**. The run directory
holds more than the scored set: 19 tasks were attempted more than once while
the harness was being fixed, and four of the public sample tasks — `build-002`,
`ops-004`, `project-001`, `tests-003` — were run alongside gold. Those four are
excluded. They ship with the open harness, their answers are public, and a
score that included them would be measuring something else.

An earlier version of this page reported 106 of 127 because it counted them.
The export is now filtered by the suite file rather than trusted to contain
only the suite, so this cannot recur.

Eight further runs are excluded, under the model ids `minimax/minimax-m3` and
`openrouter/minimax/minimax-m3`. Both are mistyped; OpenCode could not resolve
either, and all eight died in under five seconds without an agent ever starting.
They are launch failures, not attempts, and counting them as failed tasks would
have deflated the score with a typo.

## Two solves scored at the floor

`ops-010` and `ui-auto-005` hit the wall-clock limit, and the agent was
terminated before it reported any token usage. Both workspaces graded clean
afterwards, so both are passes — a timeout and a passing workspace are two
separate facts here and neither is collapsed into the other.

With no usage to read, the harness cannot verify what they cost, so it awards
them the 0.25 floor rather than full marks. In these two cases that is also
close to accurate: an agent that ran out its wall clock did not do it cheaply.

## Where the points went

Of the points not earned, the larger share belongs to outright failures and the
rest to solves that went over the token allowance.

The concentration is in `interaction`, which passed 82.6% of its tasks and
earned 53.5% of its points — a gap nothing else in the suite comes near. Six of
the ten largest single-task losses are `ui-auto` tasks. The two largest losses
overall are `coredata-003`, a difficulty-8 solve that cost 392,767 tokens, and
`ops-009`, a difficulty-6 solve that cost 724,975. Both are at the floor.

`build` reads badly at 20 of 70 points, and the sample is two tasks. One passed,
one did not. Nothing should be concluded from it.

## Isolation

This run was **not** sandboxed. The agent's web tools were off and its
configuration was replaced with a hermetic one, but the process was not confined
to a VM and host egress was open. That is stated on every run and it matters
here: it is a development-grade number, not a sealed one.
