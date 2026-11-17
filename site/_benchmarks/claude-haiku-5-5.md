---
title: "anthropic/claude-haiku-5-5, Gold Suite 1.2, 135/148 passed"
date: 2026-11-09
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: claude-haiku-5-5
model: "anthropic/claude-haiku-5-5"
harness: "opencode 1.18.31"
tasks: 148
passed: 135
description: >-
  AppleBench results for anthropic/claude-haiku-5-5 on Gold Suite 1.2:
  135 of 148 tasks completed to a verified result (91.2% pass rate),
  with cost, active time, per-category results,
  and every task.
---
This report uses the latest valid attempt for each task.

**9 November 2026.** All 148 tasks were run on 9 November with OpenCode 1.18.31,
calling `claude-haiku-5-5` directly through the Anthropic API at the provider's
default configuration, which Anthropic documents as `medium` effort. The run
sent no effort setting, so the API default applied, and the report records it as
`medium`. Every task was verified before the run: the reference solution passes it
and a run that changes nothing fails it. Simulator tasks are pinned to iOS 27.2.

All 13 failures were completed runs, with none ended by a timeout or an output
limit. The five end-to-end tasks ran longest, between 6 and 13 minutes each.

**Update, 13 November 2026.** Seven tasks were run again after task, grader and prompt changes:
`composition-002`, `composition-004`, `composition-005`, `ops-005`, `ops-022`, `system-003`
and `widget-002`. Four of them now pass (`composition-004`, `ops-022`, `system-003`,
`widget-002`), which moves the total from 131 to 135. Each task was re-verified before its
rerun: the reference solution passes it and a run that changes nothing fails it.
