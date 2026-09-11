# AppleBench site

The Jekyll site for AppleBench Gold Suite 1.2, published at
<https://afterxleep.github.io/AppleBench>.
Deployed by `.github/workflows/pages.yml` on every push to `main` that touches
this directory.

```bash
cd site
bundle install
bundle exec jekyll serve
```

## Structure

| Path | What it is |
|---|---|
| `index.html` | Home |
| `benchmark.md` | What the benchmark contains and what a pass proves |
| `methodology.md` | Execution model, isolation, recorded variables, known limits |
| `benchmarks.html` | Index of published runs |
| `_benchmarks/` | One page per published run |
| `_data/benchmarks/*.csv` | Chart source data, exported by the harness |
| `_includes/chart-*.html` | The charts |

## Publishing a run

Never hand-write the numbers. Export them from the run artifacts so every
figure on the site traces back to a `result.json`:

```bash
./Scripts/publish-report.sh 2026-09-01-sonnet-5
```

That writes `Reports/<slug>.csv`, `Reports/<slug>.json`, and
`site/_data/benchmarks/<slug>.csv`. Then add `site/_benchmarks/<slug>.md`:

```yaml
---
title: "Model name, N tasks, X%"
date: 2026-09-01
suite: gold
data: 2026-09-01-sonnet-5      # must match the CSV filename
model: anthropic/claude-sonnet-5
harness: opencode 1.18.23
lede: One or two sentences on what the run showed.
---
```

The `benchmark` layout reads `_data/benchmarks/<data>.csv` and renders the
stat tiles, charts, and full table from it. The prose in the file goes below
the charts.

The current public suite name and immutable report revision live in
`_data/suite_revisions.yml`. Gold Suite 1.2 retains revision id `2026-09-10`,
which is the value already embedded in its published reports.

**State the selection rule.** If a task was attempted more than once and the
published number depends on which attempt counts, say so on the page. That
sentence changes the headline and a reader cannot infer it from the data.

### Recalibration without rewriting history

Keep every original `result.json` immutable. When a grader is later proven
wrong, place an `adjudication.json` beside that run with the corrected grader
verdict, the evidence, and the source run ID. Aggregation applies the correction
while retaining the original artifact for audit.

When only some tasks are rerun, merge those live artifacts into the last
published report instead of rebuilding a model from an incomplete directory:

```bash
./Scripts/publish-report.sh minimax-m3 .applebench/runs gold \
  --attempt latest \
  --model minimax/MiniMax-M3 \
  --suite-file .applebench/taskset/Examples/Suites/gold.yaml \
  --base-report Reports/minimax-m3.json
```

Live runs replace matching run IDs; untouched tasks stay frozen from the base
report. Use an adjudication only when saved evidence proves the grader was
wrong. Rerun the model when the task contract itself changed.

## Charts

Server-rendered CSS and inline SVG. No chart library, no client-side data
fetch, and no chart that depends on JavaScript having run. The only script on
the site is the theme toggle.

The results index (`benchmarks.html`) compares every run on the current suite
with pass rate, cost per verified pass, active time per verified pass, and pass
rate vs total cost. These stay separate so an authored weighting cannot hide a
tradeoff. `_includes/chart-leaderboard.html` owns that comparison. Per-run pages
keep their own category, cost-vs-time, and task-matrix charts.

Series colors come from a CVD-validated categorical palette defined as custom
properties in `assets/css/main.scss`. Both themes are separately chosen sets,
not an automatic inversion. Charts with more than one series encode identity
twice (color plus shape or a direct label) and offer a table view, so nothing
is readable by color alone.
