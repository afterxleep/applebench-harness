---
title: "Open the harness, keep the answers"
date: 2026-08-27 15:00:00 -0500
tags: [contamination, design]
lede: >-
  Closing the whole benchmark defends against one threat and ignores the other.
  Here is the split, and why rotation matters more than secrecy.
---

There are two ways a benchmark stops measuring anything, and they get
conflated constantly.

**In-run cheating.** An agent with web access finds the benchmark on GitHub
mid-evaluation and reads the fixture, or the expected diff, or the grader
assertions. This is the fast version. It happens in minutes, on the very
first run after publication.

**Pretraining contamination.** Task text gets scraped, ends up in a training
corpus, and a future model has effectively memorized the answers. This is the
slow version. Months, not minutes, and silent. Nothing in the run
looks wrong.

These need different defenses, and people reach for the wrong one.

## Closing the repository only solves the slow one

Keeping everything private does nothing about in-run cheating, because that
threat does not depend on the source being public. An agent that can search
the web can find *something*, and an agent that can reach the internet during
an evaluation is not being evaluated under controlled conditions at all.

The fix for the fast threat is sandboxing the run: no internet, no search,
standard toolchain only. AppleBench does this regardless of what is published,
and it would need to whether or not the repository were open.

So the marginal value of going fully closed is lower than it feels. It buys
you the slow-leak defense and nothing else, at the cost of a benchmark
nobody can inspect, reproduce, or trust. Reviewers reasonably assume a closed
benchmark is hiding weak results.

## The split

- **Open:** the harness. Grading engine, task schema, fixture-generation
  tooling, the grader types, the isolation model, the tests that prove the
  harness behaves. Everything you would need to audit whether a reported
  number is honest.
- **Private:** the gold set. 123 scoring tasks: prompts, fixtures, expected
  outputs. Published scores come from these and only these.
- **Public and never scored:** a small leakable subset that ships with the harness so
  it can be run, demonstrated, and tested end-to-end without touching gold.

`./Scripts/check-task-set.sh` fails the build if gold and dev ever overlap, if
a task lands in neither, or if a referenced fixture goes missing. The
partition is enforced, not maintained by discipline.

## Secrecy is a delay, not a defense

Here is the part that matters more than the split.

A private set is not permanently private. It leaks through transcripts,
through screenshots, through the people who run it, through the reports that
describe what failed. Every published run leaks a little. The question is not
whether the gold set survives. It is what happens when it does not.

The answer has to be rotation. AppleBench fixtures are XcodeGen manifests with
templated defects, so the private set can be re-seeded: new bundle
identifiers, new defect placements, regenerated projects. A leaked transcript
from last quarter stops being a valid key.

```bash
./Scripts/rotate-private-set.sh 2026-q4
```

Closed answers buy time. Rotation is what keeps a benchmark alive past its
first year. Anyone building one of these should plan for the second thing on
day one, because the first thing has an expiry date whether or not you
acknowledge it.
