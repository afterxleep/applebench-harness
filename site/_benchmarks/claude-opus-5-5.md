---
title: "anthropic/claude-opus-5-5, Gold Suite 1.2, 146/148 passed"
date: 2026-11-13
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: claude-opus-5-5
model: "anthropic/claude-opus-5-5"
harness: "opencode 1.18.31"
tasks: 148
passed: 146
description: >-
  AppleBench results for anthropic/claude-opus-5-5 on Gold Suite 1.2:
  146 of 148 tasks completed to a verified result (98.6% pass rate),
  with cost, active time, per-category results,
  and every task.
---

**13 November 2026, updated 14 November.** All 148 tasks were run with OpenCode 1.18.31,
calling `claude-opus-5-5` directly through the Anthropic API at the provider's default
`medium` effort, one task at a time. Every result was then reviewed against its diff, graders
and the agent's recorded commands; no run read a solution, a withheld test or another run.

The first pass scored 143 of 148. The review found three failures that were not the model's:
`ops-026` and `g2-visual-003` were correct answers a grader's wording rejected, and
`interaction-005` died on a provider error before the agent wrote anything. After the two
graders were widened and re-verified, those three were run again and passed, which gives 146.
Two failures stand: `swiftdata-010` (a stray `.modelContainer` call without `import SwiftData`
broke the build) and `composition-002` (a stale import error stays set after a successful
retry). The review also marks `ops-022` as a pass that proves little: its grader matches the
word the agent used to say the simulator did not come back.

The attempt rule is `latest`, so a rerun replaces the result it was run for; the original
runs stay in the record.
