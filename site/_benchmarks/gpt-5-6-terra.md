---
title: "openai/gpt-5.6-terra, Gold Suite 1.2, 126/147 passed"
date: 2026-09-11
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: gpt-5-6-terra
model: "openai/gpt-5.6-terra"
harness: "opencode, opencode 1.18.20, opencode 1.18.30"
tasks: 147
passed: 126
description: >-
  AppleBench results for openai/gpt-5.6-terra on Gold Suite 1.2:
  126 of 147 tasks completed to a verified result (85.7% pass rate),
  with cost, active time, per-category results,
  and every task.
---
**Rerun pending.** Some tasks in this run were later found to be compromised.
This model will be rerun on them, and these results will change when it is.

The isolation audit invalidated Terra's original `interaction-005` pass because
that run inspected harness documentation and unrelated fixtures. The task was
rerun from a fresh workspace under the corrected seal and passed the trajectory,
build, and file graders without protected benchmark access.
