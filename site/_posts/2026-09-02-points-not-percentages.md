---
title: "Points, not percentages"
date: 2026-09-02 06:00:00 -0500
tags: [scoring, results]
lede: >-
  MiniMax M3 passed 82.9% of the gold suite and earned 72.5% of the points
  available. The gap between those two numbers is the reason AppleBench now
  scores in points.
---

MiniMax M3 solved `ops-009` — an operational loop through `xcodebuild` and
`simctl`, difficulty 6. The workspace it left behind builds, runs, and passes
every grader. It is a pass by any reading.

It took 724,975 tokens to get there.

Under a pass rate that is one tick, identical to the tick for `coredata-001`,
which the same model solved in 7,866. Every benchmark number we have published
so far has treated those two as the same event. They are not the same event,
and anybody who has watched an agent thrash through a build loop knows it.

So the headline is now points.

## What a task is worth

```text
face value  = 10 × difficulty                     difficulty 1–10 → 10–100 points
budget      = 50,000 total tokens                 flat, the same for every task
efficiency  = clamp(budget / tokens, 0.25, 1.0)   unreported tokens → 0.25
points      = passed ? face value × efficiency : 0
```

A difficulty-6 task is worth 60 points. Solve it inside the allowance and you
keep all 60. Spend twice the allowance and you keep 30. Spend fourteen times it,
as `ops-009` did, and you keep 15 — the floor, because doing the work badly is
still not the same as not doing it.

Fail and you get nothing, and the task's 60 points stay in the denominator. The
ceiling belongs to the suite, not to the model.

## The allowance is flat, and that was not the plan

The obvious design gives harder tasks a bigger budget. We built it that way
first and then looked at the data, which declined to cooperate: across this run
the median solve cost between 14,000 and 26,000 tokens at every difficulty from
1 to 7. Spend does not track authored difficulty. It tracks whether the agent
found the problem in the first ten minutes or went looking for it.

Scaling the allowance by difficulty would have encoded a relationship that is
not there, and would have quietly forgiven exactly the runs worth catching — the
hard-task thrash. So difficulty decides what a task is worth, and every task
gets the same 50,000 tokens to earn it.

50,000 is a judgment, not a measurement. It sits above the 75th percentile of
every solve observed here, so ordinary work is not penalized. It is frozen under
a specification id, `points-v1`, that every published run records, and changing
it is a scoring revision recomputed from the stored exports — not a reason to
re-run anything.

## What it does to MiniMax M3

**4,304 of 5,940 points. 102 of 123 tasks.** First attempt per task, gold suite
only, revision 2026-08-31, through OpenCode 1.18.25 on Xcode 26.6.

Of the points it did not earn, the larger share went to tasks it failed outright
and the rest to solves it paid too much for. Most solves cleared the allowance
and scored full marks; the ones that did not are the interesting ones.

{% assign rows = site.data.benchmarks['minimax-m3'] %}
{% include chart-points-by-category.html rows=rows %}

Read that against the pass rates and one category separates:

{% include chart-pass-by-category.html rows=rows %}

`interaction` passed 82.6% of its tasks and earned 53.5% of its points. Nothing
else in the suite has a gap like that. Six of the ten largest single-task losses
in the whole run are `ui-auto` tasks: driving the app on a simulator, finding
elements, writing XCUITests that hold. `ui-auto-008` cost 140,740 tokens for a
difficulty-7 solve. `ui-auto-006`, 131,295 for a difficulty-6.

The model can do UI automation. It cannot do it cheaply, and it takes a lot of
attempts to find out what is on screen. A pass rate had no way to say that.

{% include chart-points-by-difficulty.html rows=rows %}
{% include chart-cost-vs-time.html rows=rows %}

The full per-task table, every grader outcome, and the exported data are on the
[run's page]({{ '/benchmarks/minimax-m3/' | relative_url }}).

## The part that matters for later

Every term in that formula depends only on the task it belongs to: its authored
difficulty, its verdict, and what that one run spent. Nothing is normalized
against the rest of the set, against other models, or against how many tasks the
suite happens to hold.

That is not an aesthetic preference. It is what makes the suite extensible.
When a second scoring set lands, the models already measured are run **against
the new tasks only**, and their points are added to what is published. No
previously measured task is re-run and no previously published per-task number
moves. A score computed over 123 tasks and a score computed over 20 more are the
same kind of thing, and they add.

The alternative — any score normalized across a cohort — means every model in
the table has to be re-run every time the suite grows. At current prices that is
the difference between a benchmark that grows and one that gets frozen the day
it is published.

## What points still do not tell you

They do not compare across suite revisions. They do not compare across scoring
specifications. And they are deliberately not a dollar figure: cost and
wall-clock time are reported alongside, unweighted, because provider pricing
moves and a score that moved with it would be measuring the wrong thing.

For the record, this run cost $5.31 and 7.9 hours for 4.87 million tokens. That
is cheap. It is also not the score, and conflating the two is how you end up
ranking providers' price lists instead of their models.
