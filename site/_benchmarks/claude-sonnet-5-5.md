---
title: "anthropic/claude-sonnet-5-5, Gold Suite 1.2, 145/148 passed"
date: 2026-11-12
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: claude-sonnet-5-5
model: "anthropic/claude-sonnet-5-5"
harness: "opencode 1.18.31"
tasks: 148
passed: 145
description: >-
  AppleBench results for anthropic/claude-sonnet-5-5 on Gold Suite 1.2:
  145 of 148 tasks completed to a verified result (98.0% pass rate),
  with cost, active time, per-category results,
  and every task.
---

**12 November 2026, updated 13 November.** All 148 tasks were run with OpenCode 1.18.31, calling
`claude-sonnet-5-5` directly through the Anthropic API at the provider's default `high` effort,
one task at a time. Every result was then reviewed against its diff, graders and the agent's
recorded commands; no run read a solution, a withheld test or another run.

The review found four failures that were the task's fault, not the model's. After the tasks
were fixed and re-verified, those four (`composition-001`, `ops-015`, `swiftdata-007`,
`ui-auto-014`) were run again and passed, and the result moved from 141 to 145. The three
remaining failures stand: `composition-002` (a deleted ledger is reseeded at launch),
`composition-003` (the map does not show every stop) and `coredata-004` (a merge policy that
does not compile under Swift 6).
