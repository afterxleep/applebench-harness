---
title: "openrouter/deepseek/deepseek-v4-flash-0731, gold suite, 99/148 passed"
date: 2026-09-09
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: deepseek-v4-flash-0731
model: "openrouter/deepseek/deepseek-v4-flash-0731"
harness: "opencode, opencode 1.18.20, opencode 1.18.30"
tasks: 148
passed: 99
description: >-
  AppleBench results for openrouter/deepseek/deepseek-v4-flash-0731 on the gold suite:
  99 of 148 tasks completed to a verified result (66.9% pass rate),
  with cost, active time, per-category results,
  and every task.
---
## September 10 composition expansion

DeepSeek completed `composition-001` and `composition-004`, finishing the new
set 2/5. It completed `composition-002` with a failing workspace and reached
the old wall-clock cap on `composition-003` and `composition-005`. No result
was rerun.

Its earlier `ops-027` result remains a model/provider timeout: the session
emitted no tool call and never attempted screen capture, so the later Screen
Recording preflight finding does not explain that run.
