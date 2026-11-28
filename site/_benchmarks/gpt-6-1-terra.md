---
title: "GPT-6.1 Terra, Gold Suite 1.3, 172/178 passed"
date: 2026-11-28
suite: gold
suite_revision: "2026-11-28"
attempt: "latest"
data: gpt-6-1-terra
model: "openai/gpt-6.1-terra"
harness: "opencode 2.3.2"
tasks: 178
passed: 172
description: >-
  AppleBench results for GPT-6.1 Terra on Gold Suite 1.3:
  172 of 178 tasks completed to a verified result (96.6% pass rate),
  with cost, active time, per-category results,
  and every task.
---
This report uses the latest valid attempt for each task.

**28 November 2026: first run, Gold Suite 1.3.** All 178 tasks were run on 28 November, one at a time, calling `gpt-6.1-terra` through OpenAI with a ChatGPT sign-in at `medium` effort, the default on OpenAI's model page. It ran on OpenCode 2.3.2. Cost is computed from the models.dev list price ($1 in, $5 out, $0.05 cached read per million tokens); OpenCode reports $0 on a ChatGPT sign-in. The run was paused after seven tasks so other models could finish their runs, then resumed.

Every run was reviewed. Two failures were overturned because the grader was stricter than the prompt: ops-002 (the summary had every count and both failing test names, but the check wanted "total" and "test" on one line) and composition-001 (the report included the last note in full, but the text system wrapped it at a hyphen, and the test searched for it unbroken).

The six failures:

- foundationmodels-005: its basket holds a lock while notifying observers. The first hidden test never finished and was stopped after 30 minutes; grading it again hung the same way, so it is recorded as a fail.
- foundationmodels-006: each retry runs on a separate session, so the reply never reaches the conversation.
- storekit-001: the scheme points to the StoreKit configuration one folder too high.
- ops-007: no boot command was run.
- ui-auto-008: it shipped a landscape test it knew fails, without fixing the layout.
- composition-005: the shared link's accessibility value is not a URL.
