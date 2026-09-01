# AppleBench site

The Jekyll site published at <https://afterxleep.github.io/AppleBench>.
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
| `blog.html`, `_posts/` | The blog |
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

**State the selection rule.** If a task was attempted more than once and the
published number depends on which attempt counts, say so on the page. That
sentence changes the headline and a reader cannot infer it from the data.

## Charts

Server-rendered CSS and inline SVG. No chart library, no client-side data
fetch, and no chart that depends on JavaScript having run. The only script on
the site is the theme toggle.

Series colors come from a CVD-validated categorical palette defined as custom
properties in `assets/css/main.scss`. Both themes are separately chosen sets,
not an automatic inversion. Charts with more than one series encode identity
twice (color plus shape or a direct label) and offer a table view, so nothing
is readable by color alone.
