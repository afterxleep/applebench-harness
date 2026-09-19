---
title: "anthropic/claude-haiku-4-5-20251001, Gold Suite 1.2, 106/148 passed"
date: 2026-09-19
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: claude-haiku-4-5-20251001
model: "anthropic/claude-haiku-4-5-20251001"
harness: "opencode 1.18.31"
tasks: 148
passed: 106
description: >-
  AppleBench results for anthropic/claude-haiku-4-5-20251001 on Gold Suite 1.2:
  106 of 148 tasks completed to a verified result (71.6% pass rate),
  with cost, active time, per-category results,
  and every task.
---

`ui-auto-003`, `ui-auto-004`, `ui-auto-006`, `ui-auto-010` and `ui-auto-011`
carry a reviewed adjudication: the model added its new test beside the existing
tests without changing them, which the corrected file check allows.
`ui-auto-014` checks keyboard dismissal with `keyboards.count`, which the
corrected check now accepts.
