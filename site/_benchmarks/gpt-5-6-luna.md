---
title: "openai/gpt-5.6-luna, Gold Suite 1.2, 113/147 passed"
date: 2026-09-10
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: gpt-5-6-luna
model: "openai/gpt-5.6-luna"
harness: "opencode, opencode 1.18.20, opencode 1.18.30"
tasks: 147
passed: 113
description: >-
  AppleBench results for openai/gpt-5.6-luna on Gold Suite 1.2:
  113 of 147 tasks completed to a verified result (76.9% pass rate),
  with cost, active time, per-category results,
  and every task.
---
The isolation audit invalidated Luna's `networking-004` pass because that run
read prior-run material. It is excluded rather than counted as either a pass or
a model failure, leaving this report one task short of the 148-task suite.
`interaction-005` was measured again under the corrected seal, and `ops-027`
was run after Screen Recording permission was granted; both clean replacements
passed. Published cost uses the pinned model-owner list price because this
provider reported `$0` for the run-level cost field.
