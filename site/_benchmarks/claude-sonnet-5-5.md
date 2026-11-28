---
title: "Sonnet 5.5, Gold Suite 1.3, 176/178 passed"
date: 2026-11-26
suite: gold
suite_revision: "2026-11-28"
attempt: "latest"
data: claude-sonnet-5-5
model: "anthropic/claude-sonnet-5-5"
harness: "opencode 1.18.31, opencode 2.3.0, opencode 2.3.2"
tasks: 178
passed: 176
description: >-
  AppleBench results for Sonnet 5.5 on Gold Suite 1.3:
  176 of 178 tasks completed to a verified result (98.9% pass rate),
  with cost, active time, per-category results,
  and every task.
---
**28 November 2026: Gold Suite 1.3.** Thirty framework tasks for the iOS 27 SDK join the suite, 178 tasks in all. 30 of 30 passed. Four runs were first recorded as fails because the agent named its own workspace with a wildcard over the runs folder; the sandbox refused the listing, nothing came back, and every graded test passed, so they count as passes. Through the Anthropic API at `high` effort. A few of the new tasks were corrected after review (a fixed date in two hidden tests, an over-strict test in two more, the simulator to use in every prompt), every model's earlier runs of them were graded again against the corrected tests, and a run that no longer passed was run again.

**26 November 2026.** Sixteen bug-fix tasks (interaction-001 to -004, runtime-001, tests-001, -002, -005, visual-001, -003, -004, -005, activitykit-001, healthkit-001, push-002, storekit-001) now withhold their graded tests from the agent: they are absent from its checkout and the harness's copy is overlaid at grading. Every model is re-run on them and the re-runs replace the earlier results. Sonnet's sixteen re-runs are in: all 16 passed.

**12 November 2026, updated 16 November.** All 148 tasks were run with OpenCode 1.18.31, calling
`claude-sonnet-5-5` directly through the Anthropic API at the provider's default `high` effort,
one task at a time. Every result was then reviewed against its diff, graders and the agent's
recorded commands; no run read a solution, a withheld test or another run.

The review found four failures that were the task's fault, not the model's. After the tasks
were fixed and re-verified, those four (`composition-001`, `ops-015`, `swiftdata-007`,
`ui-auto-014`) were run again and passed, and the result moved from 141 to 145. On 16 November
`composition-002` was found to be the task's fault as well (its UI tests failed on taller rows
and longer sample files, and the prompt left out that a later success clears an error); once
fixed and re-verified it was run again and passed, which gives 146. The two remaining failures
stand: `composition-003` (the map does not show every stop) and `coredata-004` (a merge policy
that does not compile under Swift 6).
