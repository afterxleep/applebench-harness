---
title: "openrouter/z-ai/glm-5.3-flash, gold suite, 127/148 passed"
date: 2026-09-09
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: glm-5-3-flash
model: "openrouter/z-ai/glm-5.3-flash"
harness: "opencode, opencode 1.18.20, opencode 1.18.30"
tasks: 148
passed: 127
description: >-
  AppleBench results for openrouter/z-ai/glm-5.3-flash on the gold suite:
  127 of 148 tasks completed to a verified result (85.8% pass rate),
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

## September 10 composition expansion

GLM 5.3 Flash completed none of the five composition tasks; every run reached
the old wall-clock cap. The calibrated fixtures themselves passed with their
reference solutions, and no model result was rerun.
