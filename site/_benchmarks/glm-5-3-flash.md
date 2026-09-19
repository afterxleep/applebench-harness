---
title: "z-ai/glm-5.3-flash, Gold Suite 1.2, 139/148 passed"
date: 2026-09-16
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: glm-5-3-flash
model: "z-ai/glm-5.3-flash"
harness: "opencode, opencode 1.18.20, opencode 1.18.30, opencode 1.18.31"
tasks: 148
passed: 139
description: >-
  AppleBench results for z-ai/glm-5.3-flash on Gold Suite 1.2:
  139 of 148 tasks completed to a verified result (93.9% pass rate),
  with cost, active time, per-category results,
  and every task.
---
This report uses the latest valid attempt for each task. Four tasks affected by
grader defects were calibrated again on 9 September 2026. Two `push-002`
attempts from that calibration were excluded because a shared simulator build
hung before the model changed the workspace; the latest earlier valid
`push-002` measurement is retained. `g2-order-002` carries a reviewed
adjudication backed by its saved patch and UI trees: the model's deletion flow
passed, while a separate toggle tap was ignored by the automation layer. The
newly admitted `g2-visual-001` task was run under sealed conditions and passed
both English and Arabic device-state grading.

`ops-022` carries a reviewed adjudication: the model ran the required
`launchctl` command inside the simulator by its full path, which the task's
command check did not recognise. The check has been corrected and the task
counts as passed.

## September 10 composition expansion

GLM 5.3 Flash completed none of the five composition tasks; every run reached
the old wall-clock cap. The calibrated fixtures themselves passed with their
reference solutions, and no model result was rerun.
