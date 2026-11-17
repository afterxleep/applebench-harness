---
title: "openai/gpt-6-luna, Gold Suite 1.2, 125/148 passed"
date: 2026-11-17
suite: gold
suite_revision: "2026-09-10"
attempt: "latest"
data: gpt-6-luna
model: "openai/gpt-6-luna"
harness: "opencode 2.3.0"
tasks: 148
passed: 125
description: >-
  AppleBench results for openai/gpt-6-luna on Gold Suite 1.2:
  125 of 148 tasks completed to a verified result (84.5% pass rate),
  with cost, active time, per-category results,
  and every task.
---
This report uses the latest valid attempt for each task.

**17 November 2026.** All 148 tasks were run on 16 and 17 November, one at a time,
calling `gpt-6-luna` through OpenAI with a ChatGPT sign-in, at the provider's default
configuration, which OpenAI documents as `medium` effort. This model ran on OpenCode
2.3.0; the other models on this suite ran on OpenCode 1.18.31. The sandbox, task set,
graders and simulator runtime (iOS 27.2) are the same. Every task was verified before
the run: the reference solution passes it and a run that changes nothing fails it.

Cost is computed from the models.dev list price for `openai/gpt-6-luna` ($0.10 in,
$0.50 out, $0.01 cached read per million tokens), as for every model on this suite.

One task, `ui-auto-005`, was run again: the provider returned an HTTP 400 error that
ended the first attempt partway through, which is an infrastructure failure rather
than a result. The rerun passed. The other 23 failures were completed runs reviewed
as the model's own.

Ten framework tasks added after Gold Suite 1.2 were also run; they belong to the
next suite revision and are not part of this score.
