---
title: "GLM 5.3 Flash does 99% of Sonnet 5.5's iOS work for 38% of the price"
date: 2026-11-13
lede: "On 148 real Apple-platform tasks, the two models pass almost the same work. Sonnet is faster; GLM costs well under half as much."
---

If you hand an iOS bug to a coding agent, does it matter whether Claude Sonnet 5.5 or GLM 5.3 Flash is behind it? On AppleBench, barely in what gets done, and a lot in what it costs and how long you wait. Sonnet passed 146 of 148 tasks and GLM 144. Sonnet's run cost $12.51 at list price and GLM's $4.71. GLM took about twice as long on a typical task.

![AppleBench score: Sonnet 5.5 96.9%, GLM 5.3 Flash 94.0%]({{ '/assets/img/blog/score.svg' | relative_url }})

## What we ran

AppleBench Gold Suite 1.2 is 148 tasks on real Xcode projects: crashes, broken builds, state that leaks between screens, Swift concurrency bugs, SwiftData and Core Data, StoreKit, HealthKit, widgets, Live Activities, layouts that break at large text sizes, UI tests to write, and operational work such as driving simulators and signing builds. A task passes only when the harness's own graders agree: a build, unit and UI tests that are kept from the agent wherever the task is a fix, runtime checks on a simulator, and checks on the commands the agent actually ran. Every agent runs in a sandbox that keeps it away from the answers.

Both models ran through OpenCode, one task at a time, at each provider's default effort: `high` for Sonnet, through Anthropic's API, and `max` for GLM, through OpenRouter. We ran Sonnet at `high`, Anthropic's default, on purpose. Every step above it doubles or quadruples the bill, which is hard to justify for everyday coding work.

## The numbers

| | **Sonnet 5.5** | **GLM 5.3 Flash** |
|---|---|---|
| Tasks passed | 146 / 148 | 144 / 148 |
| AppleBench score | 96.9% | 94.0% |
| Hardest tasks passed (difficulty 8–10) | 24 / 25 | 23 / 25 |
| Total cost (list price) | $12.51 | $4.71 |
| Cost per percentage point | $0.129 | $0.050 |
| Median time per task | 96 s | 224 s |
| Slowest tenth of tasks took over | 243 s | 902 s |

The score weights each task by how many models fail it, so a task almost every model passes counts for less than one most models miss.

## Where they differ

The two models solve the same work in seven of nine categories: every build, interaction, layout, runtime, project and test task. The gap sits in two places.

| Category | Sonnet 5.5 | GLM 5.3 Flash |
|---|---|---|
| Frameworks (66) | 65 | 65 |
| Ops (28) | 28 | 27 |
| End to end (5) | 4 | 3 |
| Interaction (27), visual (9), runtime (5), project (4), tests (3), build (1) | all | all |

The end-to-end tasks are the hardest in the suite: each asks for a small feature end to end, from data model to screens to tests, and grades it with hidden unit and UI tests. Sonnet missed one of five and GLM two. Outside them, GLM missed a simulator status report and a StoreKit task; Sonnet's other miss is a Core Data merge policy that does not compile in Swift 6 mode.

## Cost

GLM 5.3 Flash costs about 38% of what Sonnet does for the same suite, and reaches about 99% of Sonnet's passes.

![AppleBench score against total list-price cost]({{ '/assets/img/blog/score-vs-cost.svg' | relative_url }})

The bill is not driven by how much the models write. GLM produced 0.6M output tokens and Sonnet 0.4M. The difference is in what each pays to read. Sonnet served almost all of its 18M prompt tokens from Anthropic's cache, which is billed at a fraction of the input price. GLM sent 9.6M tokens of uncached input on top of 99M cached, and still came out at well under half the price because its per-token price is so much lower.

## Time

The catch is time. GLM takes about twice as long on a typical task, and on its slowest tasks the gap widens: one task in ten took GLM over fifteen minutes. Across the suite, Sonnet's runs took about six hours and GLM's about fifteen.

![Active time per percentage point: Sonnet 5.5 1.9 minutes, GLM 5.3 Flash 7.9 minutes]({{ '/assets/img/blog/time-per-point.svg' | relative_url }})

## Which one to use

If you sit and wait for the agent, pick Sonnet: it finishes most fixes in a minute or two, and on the hardest feature work it is a little more reliable. If the agent runs unattended, in CI or in bulk, GLM gets almost the same work done for well under half the price, and the extra minutes cost you nothing.

## How to read these numbers

- Costs are at each model's list price per token, the same way for every model, not what a particular plan or gateway bills.
- Effort is each provider's documented default, not the maximum. Higher effort would raise both scores and both bills.
- A single run per task. A three-task gap is within what a second run can move, so treat the two as close on capability and far apart on cost and speed.

Per-task results for both models, with every grader's verdict, are on the [Results page]({{ '/benchmarks/' | relative_url }}).
