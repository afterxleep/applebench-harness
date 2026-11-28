---
title: "GPT-6.2 Sol, Gold Suite 1.3, 176/178 passed"
date: 2026-11-26
suite: gold
suite_revision: "2026-11-28"
attempt: "latest"
data: gpt-6-2-sol
model: "openai/gpt-6.2-sol"
harness: "opencode 2.3.2"
tasks: 178
passed: 176
description: >-
  AppleBench results for GPT-6.2 Sol on Gold Suite 1.3:
  176 of 178 tasks completed to a verified result (98.9% pass rate),
  with cost, active time, per-category results,
  and every task.
---
This report uses the latest valid attempt for each task.

**28 November 2026: Gold Suite 1.3.** Thirty framework tasks for the iOS 27 SDK join the suite, 178 tasks in all. 30 of 30 passed: the ten framework tasks of 14 November were run for Sol now, with the twenty of 16 November. foundationmodels-006 was run again after its prompt was tightened, and passed. Through OpenAI with a ChatGPT sign-in at `medium` effort. A few of the new tasks were corrected after review (a fixed date in two hidden tests, an over-strict test in two more, the simulator to use in every prompt), every model's earlier runs of them were graded again against the corrected tests, and a run that no longer passed was run again.

**26 November 2026.** All 148 tasks were run on 25 November, one at a time, calling `gpt-6.2-sol` through OpenAI with a ChatGPT sign-in at `medium` effort (OpenAI's earlier Sol models and Luna default to `medium`; the GPT-6.2 Sol page names no default). It ran on OpenCode 2.3.2, the first version that routes GPT-6.2 on a ChatGPT sign-in; the other models' original runs used OpenCode 1.18.31 or 2.3.0. Cost is computed from the models.dev list price ($2 in, $10 out, $0.10 cached read per million tokens); OpenCode reports $0 on a ChatGPT sign-in.

On 26 November sixteen bug-fix tasks started withholding their graded tests, and ops-022 and widget-002 were clarified; Sol was re-run on all eighteen and those results replace the first ones. On 25 November Sol had replaced push-002's visible tests with its own; that run is recorded as a fail.

The two failures: coredata-004 (a merge policy that does not compile in Swift 6 mode) and storekit-001 (it moved `ProductCatalog.swift` out of the test target and made the tests app-hosted, so the harness's tests no longer compile).
