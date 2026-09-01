# Testing AppleBench itself

```bash
swift test
```

**120 tests across 18 suites. No Xcode, no simulator, no network.**

A benchmark that cannot be trusted to grade honestly is worse than no
benchmark, so the harness's own suite is written to be adversarial about the
harness rather than decorative about it.

The suite is protocol-driven: every external dependency, `ProcessRunning`,
`BenchmarkEnvironment`, `Grader`, `AgentAdapter`, `EventRecorder`, is
substitutable. A `FakeProcessRunner` scripts subprocess responses and a
`ScriptedAdapter` plays the part of an agent, so the runner can be driven
through every state-machine path deterministically.

## What each target covers

| Target | Focus |
|---|---|
| `AppleBenchCoreTests` | Process execution, workspace lifecycle, runner orchestration, event recording, task decoding, result serialization, results export |
| `AppleBenchGradersTests` | Each grader's pass/fail contract and its infrastructure-failure boundary |
| `AppleBenchAgentsTests` | Adapter configuration, output parsing, and VM invocation shape |

The surfaces that get the most attention are the ones where a defect would
silently corrupt a score rather than crash:

- **`ProcessRunner`**, timeout enforcement, process-group termination,
  cancellation, concurrent pipe draining, and the guarantee that no task
  string is ever interpreted by a shell. This is the suite a security review
  should read first.
- **`BenchmarkRunner`**, that graders run *after* the agent exits, that
  grader configuration is not written anywhere near the workspace until then,
  that a timeout and a passing workspace are recorded as two separate facts,
  and that a task with no graders is rejected rather than trivially passed.
- **`EventRecorder`**, 100 concurrent `record` calls into the same actor,
  asserting unique sequence numbers and in-order arrival.
- **Graders**, that a FAIL verdict and an unrunnable grader are different
  outcomes, and that a grader never reports a pass it did not observe.
- **`ResultsExport`**, that a grader summary containing commas, quotes, or
  newlines cannot split a CSV row, and that absent usage exports as empty
  rather than as zero.

## How the tests stay honest

- **No real `xcodebuild` in the unit tests.** Every grader test uses
  `FakeProcessRunner`. The only real `xcodebuild` the project runs under test
  is in `verify-fixtures.sh`, which is an integration check against the actual
  tool.
- **No real simulators in the unit tests.** Runtime grader tests use `nil` or
  fake UDIDs and assert the correct error path. Real simulator behavior is
  exercised by the fixtures.
- **Real git in `WorkspaceManagerTests`.** Clone and checkout is the one part
  of the runner that genuinely has to talk to a real binary, so it does, against temporary repositories the test creates and disposes of.
- **No assertion the compiler already proves.** A test that cannot fail is
  removed rather than kept for the coverage number.

## The integration layer

Unit tests prove the harness behaves. These prove the *task set* is sound:

```bash
./Scripts/check-task-set.sh     # gold and public-dev partition every task
./Scripts/verify-fixtures.sh    # every task fails unfixed and passes fixed
```

`verify-fixtures.sh` is the one that matters most. A fixture is only
meaningful if it FAILs with an agent that changes nothing and PASSes with the
known fix; the script asserts both halves for every task, against real
`xcodebuild`. See [AUTHORING.md](AUTHORING.md).
