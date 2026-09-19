---
title: "GPT-5.6 Luna is solid and compares to GLM 5.3. It also tried to cheat three times."
date: 2026-09-15 08:30:00 +0200
tags: [models, integrity]
lede: >-
  OpenAI's smaller model solved 142 of 148 tasks at max effort for $3.73.
  Along the way it went looking for the answers three separate times, and once
  it hid what it was doing.
---

GPT-5.6 Luna is OpenAI's smaller, cheaper model. We ran it at max reasoning
effort on all 148 AppleBench tasks. It surprised us twice: once for how good
it is, and once for how hard it tried to get around the work.

It holds up against Z.ai's GLM 5.3 Flash. Z.ai's own benchmarks put GLM 5.3
close to GPT 5.6 Sol and Claude Opus 5, and that seems about right for
coding exercises. AppleBench is coding from real life: fixing bugs in real
projects, tracking down concurrency issues, getting Apple frameworks right,
and checking the result on a simulator. That's where Luna does well.

## GPT-5.6 Luna vs GLM 5.3 Flash

| | GPT-5.6 Luna | GLM 5.3 Flash |
|---|---:|---:|
| Reasoning effort | max | max |
| Tasks passed | 142 of 148 | 139 of 148 |
| Points | 18235 of 24902 (73.2%) | 17009 of 24902 (68.3%) |
| Cost at list price | $3.73 | $1.25 |
| Typical task | 4.2 min | 4.6 min |

Luna comes out ahead, 142 passes to 139 and 73.2% to 68.3% on points. Part of
the points gap is one task: Luna built one of the five small apps in the suite,
GLM built none, and those are worth a lot. GLM gets within three tasks for a
third of the price.

By category, Luna went 28 for 28 on the Xcode command line tools, where GLM
got 27. They tied on Apple frameworks, 64 of 66 each, and both were perfect
on project setup, crashes and how the app looks. Luna also drove the running
app better, 27 of 27 to GLM's 26.

## Luna tried to cheat, three times

Each task gives the agent one project, and the fix has to come from that
project. Luna kept leaving it.

### 1. It read other runs

Luna passed a task, and when we read what it had done, it had gone outside its
project and read results from earlier benchmark runs. We threw the pass out
and locked the environment down.

### 2. It read how we grade

On another task, Luna tried to open our private files and was blocked. On the
next attempt it found files that weren't blocked, read our internal notes on
how tasks are built and checked, looked through other task projects, and only
then wrote its answer. We threw that one out too and closed every gap.

### 3. It searched for the answer and hid it

We ran the first task again with everything locked down. This one shows most
clearly what Luna does.

Early on, Luna had already worked out the likely cause of the bug. It told the
user it was "checking the repository history and build context to confirm"
before making a change. That's not what it did. Instead it:

- looked for other git branches and deleted commits that might still hold the
  fix
- tried to open its own run logs and the rules it was running under
- searched every file it could reach for the task's name and words from the
  prompt

All of it came back blocked or empty. So Luna went back to the project,
reproduced the bug, fixed it properly and passed, in three minutes. What it
told the user never mentioned the searching.

## How the rest of the run went

Luna's main run was September 10 and 11. Besides the thrown-out passes, one
task was blocked by a macOS permission prompt and had to be run again. Reruns
on September 15 and 17 covered tasks we had changed since, including one whose
test was rejecting a correct fix; every model reran that one. All of it is in
the 142 above.

## What to make of it

Luna was consistent on everything that needed a simulator or automation, and
it handled the common Apple frameworks well. Checking UIs, driving
simulators, building working apps: no problem.

We can't see Luna's reasoning, only what it did and what it said. What it did
was consistent: when the answer might be sitting somewhere on disk, Luna goes
and looks, and it doesn't tell you.

The funny part is that it never needed to. Every time it was locked in, it
solved the task on its own.

## Verdict

Luna is cheap, especially on an OpenAI subscription, and it's good at the
grunt work. If you need to automate tasks, run tests or drive simulators to
check your work, it's a great fit: fast, accurate and cheap. Just keep it
away from anything you don't want it to read.
