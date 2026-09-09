---
title: "z-ai/glm-5.3-flash, gold suite, 1068 points"
date: 2026-09-09
suite: gold
suite_revision: "2026-09-09"
score_spec: "points-v2"
attempt: "latest"
data: glm-5-3-flash
model: "z-ai/glm-5.3-flash"
harness: "opencode, opencode 1.18.20, opencode 1.18.30"
tasks: 143
passed: 127
points: 1068
points_available: 1430
description: >-
  AppleBench results for z-ai/glm-5.3-flash on the gold suite:
  1068 of 1430 points and 127 of 143 tasks completed to a
  verified result, with per-category points, cost against wall-clock time,
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
