---
title: "z-ai/glm-5.3-flash, Gold Suite 1.2, 143/148 passed"
date: 2026-09-16
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: glm-5-3-flash
model: "z-ai/glm-5.3-flash"
harness: "opencode, opencode 1.18.20, opencode 1.18.30, opencode 1.18.31"
tasks: 148
passed: 143
description: >-
  AppleBench results for z-ai/glm-5.3-flash on Gold Suite 1.2:
  143 of 148 tasks completed to a verified result (96.6% pass rate),
  with cost, active time, per-category results,
  and every task.
---
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
