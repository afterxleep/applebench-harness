---
title: Help pay for the runs
permalink: /donate/
lede: >-
  Every number on this site was bought with tokens. A single model costs
  between $4 and $100 to measure, and there is no sponsor behind it.
description: >-
  Why measuring a model on AppleBench costs real money, what a run actually
  buys, and how to chip in.
---

## What a run costs

AppleBench does not ask a model one question. It hands an agent 123 broken
Xcode projects, one at a time, and lets it work until the task is solved or the
clock runs out. The agent reads files, edits them, runs `xcodebuild`, reads the
errors, launches the app on a simulator, and tries again. That loop is the
whole point, and it is why the numbers mean something.

It is also why it is expensive. A frugal model that solves things quickly and
gives up early lands around **$4**. A model that reasons at length, retries,
and burns its full budget on the tasks it cannot solve lands near **$100**. The
same suite, the same tasks; the spread is the model.

Then multiply. A published comparison is several models. A model that ships a
new version has to be re-measured. A change to the suite invalidates every
number measured on the old one, so they all get run again.

## What a donation buys

Nothing is owed to anyone here, so this is not a subscription and there are no
tiers, no perks, and no roadmap you get a vote on. Money goes to one thing:
running more models, more often, and publishing what came back.

Concretely, it pays for:

- **New models measured sooner.** A release that would otherwise wait until
  there is budget gets run the week it lands.
- **Re-runs when the suite changes.** Numbers measured on a superseded revision
  are not comparable, and leaving them up while pretending otherwise is how
  benchmarks quietly become wrong.
- **Repeat runs of the same model.** One run is an anecdote. Several tell you
  how much of a score is the model and how much is luck.
- **Keeping the results free.** No paywall, no sponsored placement, no ranking
  anyone paid for.

## Chip in

{% if site.donate_url or site.donate_paypal_url %}
<div class="button-row">
  {%- if site.donate_url %}
  <a class="button button--primary" href="{{ site.donate_url }}">GitHub Sponsors</a>
  {%- endif %}
  {%- if site.donate_paypal_url %}
  <a class="button button--ghost" href="{{ site.donate_paypal_url }}">PayPal</a>
  {%- endif %}
</div>
{% endif %}

Any amount is useful, and small ones add up faster than you would think: a
handful of them is another model measured.

If you would rather not send money, the other thing that helps is telling
people the numbers exist, and telling me when one of them looks wrong. A
benchmark nobody checks is just a number I made up with extra steps.

## Where the money is not going

This is one person paying an API bill, not an organisation. There is no
company, no staff, and no infrastructure beyond a Mac and a token budget. If
donations ever cover more than the runs, that will be said here rather than
quietly absorbed.

Nothing about a donation buys influence over a result. No model is ranked
higher for money, no model is measured differently because its makers gave, and
if that ever changes it will be at the top of this page, not in a footnote.
