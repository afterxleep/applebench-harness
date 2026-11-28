---
title: "Haiku 5.5, Gold Suite 1.3, 162/178 passed"
date: 2026-11-26
suite: gold
suite_revision: "2026-11-28"
attempt: "latest"
data: claude-haiku-5-5
model: "anthropic/claude-haiku-5-5"
harness: "opencode 1.18.31, opencode 2.3.0, opencode 2.3.2"
tasks: 178
passed: 162
description: >-
  AppleBench results for Haiku 5.5 on Gold Suite 1.3:
  162 of 178 tasks completed to a verified result (91.0% pass rate),
  with cost, active time, per-category results,
  and every task.
---
**28 November 2026: Gold Suite 1.3.** Thirty framework tasks for the iOS 27 SDK join the suite, 178 tasks in all. 28 of 30 passed. Fails: foundationmodels-009 (it read the older SDK, concluded the transcript could not be edited and changed nothing) and swiftdata-013 (a save made right after the board is created is missed). In evaluations-002 it searched outside its workspace for the Evaluations package source; every search was refused or never ran, and the run is scored on its graders. Through the Anthropic API at `medium` effort. A few of the new tasks were corrected after review (a fixed date in two hidden tests, an over-strict test in two more, the simulator to use in every prompt), every model's earlier runs of them were graded again against the corrected tests, and a run that no longer passed was run again.

**26 November 2026.** Sixteen bug-fix tasks (interaction-001 to -004, runtime-001, tests-001, -002, -005, visual-001, -003, -004, -005, activitykit-001, healthkit-001, push-002, storekit-001) now withhold their graded tests from the agent: they are absent from its checkout and the harness's copy is overlaid at grading. Every model is re-run on them and the re-runs replace the earlier results. Haiku's sixteen re-runs are in: 15 passed. storekit-001 fails: its StoreKit configuration path resolves inside the .xcodeproj, so the debug paywall loads nothing.

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
