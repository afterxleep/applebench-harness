---
title: "openai/gpt-5.6-luna, Gold Suite 1.2, 114/148 passed"
date: 2026-09-10
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: gpt-5-6-luna
model: "openai/gpt-5.6-luna"
harness: "opencode, opencode 1.18.20, opencode 1.18.30"
tasks: 148
passed: 114
description: >-
  AppleBench results for openai/gpt-5.6-luna on Gold Suite 1.2:
  114 of 148 tasks completed to a verified result (77.0% pass rate),
  with cost, active time, per-category results,
  and every task.
---
The isolation audit invalidated Luna's original `networking-004` pass because
that run read prior-run material. The task was rerun from a fresh workspace
under the corrected seal and passed both the build grader and all 2 sealed
tests. `interaction-005` was also measured again under the corrected seal, and
`ops-027` was run after Screen Recording permission was granted; both clean
replacements passed. Published cost uses the pinned model-owner list price
because this provider reported `$0` for the run-level cost field.
