---
title: "GPT-6 Luna, Gold Suite 1.3, 137/178 passed"
date: 2026-11-26
suite: gold
suite_revision: "2026-11-28"
attempt: "latest"
data: gpt-6-luna
model: "openai/gpt-6-luna"
harness: "opencode 2.3.0, opencode 2.3.2"
tasks: 178
passed: 137
description: >-
  AppleBench results for GPT-6 Luna on Gold Suite 1.3:
  137 of 178 tasks completed to a verified result (77.0% pass rate),
  with cost, active time, per-category results,
  and every task.
---
**28 November 2026: Gold Suite 1.3.** Thirty framework tasks for the iOS 27 SDK join the suite, 178 tasks in all. 12 of 30 passed. Most fails are invented or guessed APIs that do not compile; in foundationmodels-004 and -012 it stopped without an edit. Through OpenAI with a ChatGPT sign-in at `medium` effort. A few of the new tasks were corrected after review (a fixed date in two hidden tests, an over-strict test in two more, the simulator to use in every prompt), every model's earlier runs of them were graded again against the corrected tests, and a run that no longer passed was run again.

**26 November 2026.** Sixteen bug-fix tasks (interaction-001 to -004, runtime-001, tests-001, -002, -005, visual-001, -003, -004, -005, activitykit-001, healthkit-001, push-002, storekit-001) now withhold their graded tests from the agent: they are absent from its checkout and the harness's copy is overlaid at grading. Every model is re-run on them and the re-runs replace the earlier results. Luna's sixteen re-runs are in: 15 passed. push-002 fails: the fix calls macOS-only Security APIs and never sets the entitlements. The re-runs used OpenCode 2.3.2.

This report uses the latest valid attempt for each task.

**17 November 2026.** All 148 tasks were run on 16 and 17 November, one at a time,
calling `gpt-6-luna` through OpenAI with a ChatGPT sign-in, at the provider's default
configuration, which OpenAI documents as `medium` effort. This model ran on OpenCode
2.3.0; the other models on this suite ran on OpenCode 1.18.31. The sandbox, task set,
graders and simulator runtime (iOS 27.2) are the same. Every task was verified before
the run: the reference solution passes it and a run that changes nothing fails it.

Cost is computed from the models.dev list price for `openai/gpt-6-luna` ($0.10 in,
$0.50 out, $0.01 cached read per million tokens), as for every model on this suite.

One task, `ui-auto-005`, was run again: the provider returned an HTTP 400 error that
ended the first attempt partway through, which is an infrastructure failure rather
than a result. The rerun passed. The other 23 failures were completed runs reviewed
as the model's own.

Ten framework tasks added after Gold Suite 1.2 were also run; they belong to the
next suite revision and are not part of this score.
