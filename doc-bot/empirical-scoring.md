---
title: "Empirical scoring"
description: "How AppleBench turns observed pass rates into an auditable 0–100 capability score."
keywords: ["empirical", "score", "weights", "points", "reports", "empirical-v1"]
topics: ["scoring", "reporting"]
category: "benchmark"
filePatterns: ["Sources/AppleBenchCore/Models/BenchmarkScore.swift", "Sources/AppleBenchCore/Models/ResultsExport.swift", "Scripts/rescore-empirical.py", "site/_includes/chart-leaderboard.html", "site/_layouts/benchmark.html"]
---

AppleBench uses the `empirical-v1` scoring specification. Each task's weight is
measured from the complete published model runs for the current suite:
`weight = min(2000, round(100 × modelCount / passingModelCount))`, with a task
no model passes earning the 2000-point cap and a universal pass worth 100. A
verified pass earns the task's full weight; a failure earns zero while its
weight stays in the denominator. The headline score is `100 × earned /
available`, published beside the raw pass rate. The authored `difficulty`
remains in run metadata but never scores.

Weights live in `site/_data/empirical_weights.json` and are recorded inside
every report JSON under `task_weights`, so any published score can be
recomputed from its own export. The score is a living number for the current
suite revision: adding a complete model changes the pass rates, so rerun
`Scripts/rescore-empirical.py` (or `applebench weights` on the run
directories) to reweight, and every complete model is rescored without being
rerun. `publish-report.sh` refuses to export without a weights file rather
than publish an unscored report. Cost, tokens, and active time do not alter
capability points; the site divides total suite cost and total active agent
time — including failures — by the score's percentage points (the 0–100
number), not by raw points.
