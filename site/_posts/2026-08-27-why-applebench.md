---
title: "Why AppleBench exists"
date: 2026-08-27 09:00:00 -0500
tags: [benchmark, design]
lede: >-
  Coding benchmarks measure whether a model can write a diff. Apple development
  is mostly the part after the diff, and nothing was measuring that.
---

Ask most coding benchmarks what they measure and the honest answer is: can the
model produce a patch that makes a test go green. That is a real skill and it
is worth measuring. It is also not what Apple development is.

Apple development is an execution loop:

```text
understand → edit → build → diagnose → run → inspect → interact → test → verify
```

The edit is one step out of nine. The other eight involve a toolchain that
gives you feedback only when you run it, in formats you have to know how to
read, with failure modes that have nothing to do with the language. A model
that writes flawless Swift and cannot get `xcodebuild` to target a simulator
is not useful to an iOS engineer.

## What "done" has to mean

The design constraint that shaped everything else: **a passing result has to
mean the app actually works**, not that the diff looked right.

So AppleBench grades the workspace, not the agent's account of it. After the
agent exits, the harness runs a fresh `xcodebuild` with clean derived data,
runs the tests, installs the product on a simulator, launches it, and watches
it survive. The agent's own successful build counts for nothing. If the agent
built it and the grader cannot, the grader wins.

That inversion is the whole product. Everything else in the harness exists to
keep it honest:

- Grader configuration is not written anywhere near the workspace until the
  agent has already exited. It cannot read the assertions and write to them.
- Prompts state the symptom, never the cause and never the file. The
  diagnosis is the task.
- Project configuration is graded by what it *resolves to*: build settings
  from `xcodebuild -showBuildSettings -json`, `Info.plist` keys read out of
  the built product. A plausible line pasted into `project.pbxproj` that does
  not take effect cannot pass.

## What got cut

The first version had tasks about Swift generics, actor isolation, and data
races. They came out.

Not because they are easy. Some were the hardest tasks in the set,
but because other benchmarks already cover language-level Swift, and overlap
buys nothing. If a model's `Sendable` reasoning is already measured somewhere
credible, measuring it again here adds noise and no signal.

What nobody else measures is whether an agent can operate the toolchain. So
that is what is left: build failures that are SDK-specific, project
configuration, simulator interaction, XCUITests, Apple frameworks, and raw
`xcodebuild`/`simctl` operational loops with every wrapper CLI stripped off
the path.

## The uncomfortable part

Building a benchmark means eventually publishing a number, and a number is
much easier to trust than it should be.

The first full run produced 33.7%. It could just as defensibly have been
26.5%. Same artifacts, same model, same day, different rule about which
attempt counts when a task was re-run after an infrastructure failure. Neither
number is wrong. Only one of them is meaningful without the sentence that
explains it.

That is why every published run here states its suite, its model, its
environment, and its selection rule, and why the harness reports a grader that
*failed* and a grader that *could not run* as two different outcomes. A
benchmark that quietly collapses those is measuring your CI stability and
calling it model capability.
