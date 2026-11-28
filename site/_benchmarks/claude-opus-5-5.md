---
title: "Opus 5.5, Gold Suite 1.3, 175/178 passed"
date: 2026-11-26
suite: gold
suite_revision: "2026-11-28"
attempt: "latest"
data: claude-opus-5-5
model: "anthropic/claude-opus-5-5"
harness: "opencode 1.18.31, opencode 2.3.0, opencode 2.3.2"
tasks: 178
passed: 175
description: >-
  AppleBench results for Opus 5.5 on Gold Suite 1.3:
  175 of 178 tasks completed to a verified result (98.3% pass rate),
  with cost, active time, per-category results,
  and every task.
---
**28 November 2026: Gold Suite 1.3.** Thirty framework tasks for the iOS 27 SDK join the suite, 178 tasks in all. 29 of 30 passed. The one fail is foundationmodels-008: each tool call was written to the audit trail twice on the graded iOS 27.2 simulator. Through the Anthropic API at `medium` effort. A few of the new tasks were corrected after review (a fixed date in two hidden tests, an over-strict test in two more, the simulator to use in every prompt), every model's earlier runs of them were graded again against the corrected tests, and a run that no longer passed was run again.

**26 November 2026.** Sixteen bug-fix tasks (interaction-001 to -004, runtime-001, tests-001, -002, -005, visual-001, -003, -004, -005, activitykit-001, healthkit-001, push-002, storekit-001) now withhold their graded tests from the agent: they are absent from its checkout and the harness's copy is overlaid at grading. Every model is re-run on them and the re-runs replace the earlier results. Opus's sixteen re-runs are in: 15 passed. storekit-001 fails: its StoreKit configuration path (`../Resources/...`) is the workspace form and resolves inside the .xcodeproj.

**13 November 2026, updated 16 November.** All 148 tasks were run with OpenCode 1.18.31,
calling `claude-opus-5-5` directly through the Anthropic API at the provider's default
`medium` effort, one task at a time. Every result was then reviewed against its diff, graders
and the agent's recorded commands; no run read a solution, a withheld test or another run.

The first pass scored 143 of 148. The review found three failures that were not the model's:
`ops-026` and `g2-visual-003` were correct answers a grader's wording rejected, and
`interaction-005` died on a provider error before the agent wrote anything. After the two
graders were widened and re-verified, those three were run again and passed, which gives 146.
`composition-002` then turned out to be the task's fault too: its UI tests could not find or
swipe a row once the app's rows were taller, broke on a longer sample CSV, and the prompt did
not say that a later success clears an earlier error. After the prompt and tests were fixed and
re-verified, Opus ran it again and passed, which gives 147. One failure stands: `swiftdata-010`
(a stray `.modelContainer` call without `import SwiftData` broke the build). The review also
marks `ops-022` as a pass that proves little: its grader matches the word the agent used to say
the simulator did not come back.

The attempt rule is `latest`, so a rerun replaces the result it was run for; the original
runs stay in the record.
