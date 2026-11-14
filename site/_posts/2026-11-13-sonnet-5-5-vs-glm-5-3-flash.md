---
title: "Sonnet 5.5 is no better than GLM 5.3 Flash at iOS work. It just costs 2.6x more."
date: 2026-11-13
lede: "Both models solve nearly the same Apple-platform tasks. One costs well under half as much."
---

GLM 5.3 Flash solves the same Apple-platform tasks as Sonnet 5.5 for about 39% of the price.

![AppleBench score: Sonnet 5.5 86.2%, GLM 5.3 Flash 84.7%]({{ '/assets/img/blog/score.svg' | relative_url }})

We ran both on all 148 tasks of AppleBench Gold Suite 1.2 at each provider's default effort: `high` for Sonnet, `max` for GLM.

Sonnet ran at `high`, Anthropic's default, on purpose. Every step above it doubles or quadruples the bill, which is not really cost effective for general coding work.

| | **Sonnet 5.5** | **GLM 5.3 Flash** |
|---|---|---|
| Tasks passed | 145 / 148 | 143 / 148 |
| AppleBench score | 86.2% | 84.7% |
| Total cost (list price) | $5.33 | $2.08 |
| Cost per percentage point | $0.062 | $0.024 |
| Median time per task | 96 s | 199 s |

Both models perform quite well on iOS work, with the exception of our most difficult end to end tasks. What's really impressive is that GLM 5.3 is about 98% of Sonnet's pass rate for 39% of the price.

![AppleBench score against total list-price cost]({{ '/assets/img/blog/score-vs-cost.svg' | relative_url }})

Paying two to four times more such a small difference no sense at all, but the catch here is time. GLM 5.3 flash takes about twice as long per task and uses far more tokens to get there, 11.2M against 0.5M, which is where Sonnet's prompt caching pays off.

![Active time per percentage point: Sonnet 5.5 2.2 minutes, GLM 5.3 Flash 8.4 minutes]({{ '/assets/img/blog/time-per-point.svg' | relative_url }})

If you sit and wait for the agent or have a, pick Sonnet. If it runs unattended or in bulk, GLM is your guy.

Per-task results for both models are on the [Results page]({{ '/benchmarks/' | relative_url }}).
