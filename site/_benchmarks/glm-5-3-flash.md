---
title: "GLM 5.3 Flash, Gold Suite 1.3, 171/178 passed"
date: 2026-11-26
suite: gold
suite_revision: "2026-11-28"
attempt: "latest"
data: glm-5-3-flash
model: "z-ai/glm-5.3-flash"
harness: "opencode, opencode 1.18.20, opencode 1.18.30, opencode 1.18.31, opencode 2.3.0, opencode 2.3.2"
tasks: 178
passed: 171
description: >-
  AppleBench results for GLM 5.3 Flash on Gold Suite 1.3:
  171 of 178 tasks completed to a verified result (96.1% pass rate),
  with cost, active time, per-category results,
  and every task.
---
**28 November 2026: Gold Suite 1.3.** Thirty framework tasks for the iOS 27 SDK join the suite, 178 tasks in all. 27 of 30 passed. Fails: foundationmodels-009, datadetection-001 (timed out on a regex rewrite that does not compile) and webkit-002 (timed out with the fix still in a scratch copy). Through OpenRouter at `max` effort. A few of the new tasks were corrected after review (a fixed date in two hidden tests, an over-strict test in two more, the simulator to use in every prompt), every model's earlier runs of them were graded again against the corrected tests, and a run that no longer passed was run again.

**26 November 2026.** Sixteen bug-fix tasks (interaction-001 to -004, runtime-001, tests-001, -002, -005, visual-001, -003, -004, -005, activitykit-001, healthkit-001, push-002, storekit-001) now withhold their graded tests from the agent: they are absent from its checkout and the harness's copy is overlaid at grading. Every model is re-run on them and the re-runs replace the earlier results. GLM's seventeen re-runs (the sixteen plus widget-002) are in: 16 passed, storekit-001 fails on its scheme path. In storekit-001 (a machine-wide search) and widget-002 (a listing of the runs root) the agent reached beyond its run's directory; the sandbox refused both, nothing came back, and the runs are scored on their graders. The re-runs used OpenCode 2.3.2.

This report uses the latest valid attempt for each task.

**Update, 8 November 2026.** 59 of the 148 tasks were run again after task, grader
and fixture changes, using OpenCode 1.18.31 at the model's default `max` effort.
The other 89 results are unchanged from earlier runs. Every simulator task is now
pinned to iOS 27.2, because the iOS 26.5 runtime is no longer installed on the
benchmark machine; the 89 retained results were produced on iOS 26.5, so this
report mixes the two runtimes. Every task was re-verified before the rerun: the
reference solution passes it and a run that changes nothing fails it.

Of the 59 re-runs, 54 passed. The five failures:

- `composition-001` and `composition-002` failed their graders on completed runs.
- `storekit-001` completed but one of four tests failed
  (`testTheDebugStoreConfigurationServesTheAdvertisedPlans`).
- `ops-022` reached the task time limit without writing the report. The model never
  ran `launchctl` inside the simulator, which the task's command check requires, so
  the earlier adjudication that counted this task as passed no longer applies.
- `widget-002` ended because the model reached its output length limit
  (`output_truncated`); its three tests failed. `runtime-001` ended the same way
  and passed.

`g2-order-002` carries a reviewed adjudication backed by its saved patch and UI
trees: the model's deletion flow passed, while a separate toggle tap was ignored by
the automation layer.

**Update, 13 November 2026.** Seven tasks were run again after later task, grader and prompt
changes: `composition-001`, `composition-002`, `composition-005`, `ops-005`, `ops-007`,
`ops-022` and `widget-002`. `composition-001` and `ops-022` now pass, and `composition-005`
now fails a UI test (`testSharedSavedLinkReopensCachedArticleFromColdLaunch`), so the total moves
from 142 to 143. The latest attempt replaces the earlier one in the score; the earlier runs are
kept in the run record.
