# AppleBench grading principles

The grading model is the single biggest lever on what AppleBench actually
measures. A grader that prescribes how the agent must do the work, rather
than checking whether the work was done, turns an honest capability signal
into a recipe test. This document states the rules every grader must follow,
and the fixtures that are exempt from them.

## The outcome rule

A grader answers **"did the work get done?"**, never **"did the
agent follow my preferred implementation?"**

Three concrete consequences fall out of that:

1. **The grader checks the artifact, not the recipe.** If the prompt
   asks for a CI cycle, the grader checks the `.xcarchive` and the
   signed `.app` and the build-settings JSON, not the prose the
   agent wrote about them. A well-written report that describes work
   that was never done is still a FAIL.

2. **The grader is tolerant of equivalent solutions.** Two ways to do
   the same thing are both correct. "xcodebuild clean" and
   `xcodebuild -alltargets clean` both clean; a grader that requires
   the first string and rejects the second is measuring vocabulary,
   not capability. The same applies to test report format, simulator
   state, file layout, anything the prompt didn't lock down.

3. **The grader is strict on the one thing the prompt actually
   required.** If the prompt says "produce an `.xcarchive`", the
   grader must verify the archive exists. If the prompt says "write
   a pass/fail report", the grader must verify the report exists and
   is non-trivial. Outcomes are the contract; everything else is the
   agent's choice.

## What each grader type does

| Grader     | What it measures                                    | When to use                                |
|------------|-----------------------------------------------------|--------------------------------------------|
| `build`    | xcodebuild succeeds and the scheme is buildable.    | Any task that produces a `.app` or `.xcarchive`. |
| `xcuitest` | The agent's UI test target compiles and the test passes. | Any task that adds a UI test.           |
| `xctest`   | The agent's unit test target compiles and the test passes. | Any task that adds a unit test.       |
| `file`     | A deliverable file exists, is non-trivial, and meets the assertions the prompt actually required. | Report / config / log / artifact deliverables. |
| `runtime`  | The app launches, survives an observation window, and does not crash. | Tasks that exercise the app on the simulator. |
| `xcodeproj`| The resolved project configuration matches the prompt's requirement (build settings, Info.plist, bundle contents). | Tasks about project wiring.        |

## File grader, in detail

The `file` grader is the most likely to drift into prescription. The
following rules keep it honest:

- **`exists: true` / `exists: false`**: does the file exist, and was
  it created or deleted by the run? This is the floor. A task whose
  only deliverable is a file should at minimum check `exists` and
  `changed`.

- **`min_size: <bytes>`**: a non-trivial size floor. Use this when
  the prompt asked for a substantive document (a report, a README, a
  manifest) and you want to catch a one-line stub. Don't use a high
  value; the floor is to defeat empty deliverables, not to measure
  verbosity.

- **`is_json: true`**: the file parses as JSON. Use this when the
  prompt asked for a JSON dump. The grader does not check the JSON
  schema; it only verifies the file is a real JSON document. Schema
  validation belongs in a separate, schema-specific grader.

- **`contains: <substring>`**: a literal substring. The grader
  treats this as a case-sensitive literal match. Use it only when
  the prompt's *content* requires a specific term, such as a field
  the task explicitly asks the agent to report, or when the
  artifact's format is fixed (a JSON key, a fixed string emitted by
  a tool).

- **`matches: <regex>`**: a regular expression. The grader treats
  this as a regex match. Use `(?i)` for case-insensitive. This is
  the most prescriptive assertion type; prefer it only when the
  prompt asked for a structured section ("the report must include
  the wall-clock time of each step") and the structured shape is
  what you want to verify, not the wording.

- **Do not check implementation strings the prompt did not require.**
  If the prompt says "use `xcodebuild`", do not grep the report for
  the string `xcodebuild`: that is checking that the agent
  remembered the tool name, not that the work was done. Check the
  artifacts instead.

## What the harness does *not* check

- **The agent's prose.** A task's prompt may ask for a written
  report. The grader verifies the report file exists, is non-trivial,
  and contains the elements the prompt required. The grader does
  not score the quality of the writing.

- **The agent's tool of choice.** A task that says "use
  `xcodebuild`" is checking that the agent knows how to drive the
  Apple toolchain. The grader checks the work, not whether the
  agent went through `xcodebuild` or a wrapper. Calibration runs
  that want to enforce raw toolchain use set `--strip-wrapper-clis`
  on the CLI: that is a separate, opt-in mechanism, not a grader
  concern.

- **The agent's internal reasoning.** A task may require
  investigation or multi-step reasoning. The grader checks the
  outcome, not the steps that led to it.

## Calibration exemption

The scoring suite is 123 tasks across eight categories. Run it with
`applebench suite <suite>` (or a task list) and `--parallel N` to match your
host's simulator budget, though 1 is the safe default: each slot boots its own
simulator, and simulators running alongside each other make `xcodebuild test`
hang against its own device.

## Worked example

One scoring task asks for a full CI cycle. Its grader went through two
iterations, and the difference between them is the whole rule:

**v1 (prescriptive):** the file grader required the report to
contain `xcodebuild clean`, `xcodebuild build`, `xcodebuild test`,
`xcodebuild -archive`, and `codesign`. A well-written report in a
different style, such as a step table, a `pass/fail` matrix or a
narrative, would FAIL even if the CI cycle itself ran perfectly.

**v2 (outcome-focused):** the file grader requires:
- `ci-report.md` exists, was changed, is at least 200 bytes
  (substantive report, exact wording irrelevant)
- `build-settings.json` exists, was changed, parses as JSON
  (real settings dump, schema irrelevant)
- the archive's `Info.plist` exists and was changed
  (a real archive was produced)
- the `Info.plist` of the app inside that archive exists and was
  changed (the archive contains a buildable app)

The build grader separately re-runs `xcodebuild` in fresh derived
data to confirm the CI cycle's build step is reproducible.

A v2 grader that says PASS is making a stronger claim than a v1
grader that says PASS: it has verified that the agent actually
produced the artifacts a CI cycle is supposed to produce, not just
that the agent wrote a sentence containing the word "xcodebuild".
