---
title: "openai/gpt-5.6-luna, gold suite, 114/148 passed"
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
  AppleBench results for openai/gpt-5.6-luna on the gold suite:
  114 of 148 tasks completed to a verified result (77.0% pass rate),
  with cost, active time, per-category results,
  and every task.
---

Two archived attempts were excluded after the isolation audit found they had
read harness-owned verification or prior-run material. `networking-004` and
`interaction-005` were measured again under the corrected seal; `ops-027` was
run after Screen Recording permission was granted. All three replacement runs
passed. The published cost uses the pinned model-owner list price because this
provider reported `$0` for the run-level cost field.
