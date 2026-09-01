# Agent harnesses

AppleBench drives an agent through the `AgentAdapter` seam. Four adapters
ship in `AgentCatalog.defaultRegistry()`; all four implement the same
protocol, so the runner treats them identically.

### `opencode`, the real harness

The default. Runs OpenCode non-interactively against the workspace as the
working directory. Because OpenCode is multi-provider, a single fixed harness
reaches every model, `--model <provider/model>` selects it and `--effort`
(maps to OpenCode's `--variant <minimal|low|medium|high|max>`) sets
provider-specific reasoning effort.

**Command line the agent actually sees:**

```text
opencode run --format json --pure --auto [--model <model>] [--variant <effort>] [<extra-agent-args…>] <prompt>
```

- `--format json`, emit one JSON object per line, one per event. AppleBench
  preserves every line verbatim as an `agent_event` in `events.jsonl`; the
  `OpenCodeOutputParser` extracts tool/message/usage classification from each
  line.
- `--pure`, disable OpenCode's external plugins so nothing leaks in from the
  user's environment.
- `--auto`, auto-approve the permissions the benchmark has explicitly granted
  (edit, bash) so runs never block on prompts.
- `--model <provider/model>` and `--variant <effort>` are passed only when the
  CLI flags are present.

**Hermetic OpenCode configuration.** Before the agent launches, AppleBench
writes a benchmark-owned `opencode.json` to the run directory and points
`OPENCODE_CONFIG` at it (which replaces the user's global config). The file
denies `webfetch` in both `tools` and `permission` so the agent's toolset has
no internet access, and auto-allows the remaining permissions:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "edit": "allow",
    "bash": "allow",
    "webfetch": "deny"
  },
  "tools": {
    "webfetch": false
  }
}
```

**Environment.** The agent gets a minimal environment, `PATH`, `HOME`,
`USER`, `TMPDIR`, `SHELL`, `TERM`, `LANG`, `LC_ALL`, plus only the variables
explicitly allowlisted via repeated `--allow-env NAME`. Nothing else from the
host shell leaks in.

**Telemetry capability:** `structured`, tool events, messages, and per-step
token usage are all parsed from the JSON stream.

### `opencode-vm`, the same harness, hard-isolated in a Tart VM

Register identifier: `opencode-vm`. Triggered when the CLI is invoked with
`--vm <image>`. Boots a user-prepared Tart image (Xcode + OpenCode installed,
models authenticated) and runs the agent inside it; stops the VM after the
run. Grading still happens on the host, against the workspace, after the VM
has been stopped, the agent and the evaluator never share a running machine.

**Confinement properties:**

- The guest sees **exactly two host folders**, the run workspace (read-write,
  virtiofs) and a read-only mount containing only the hermetic OpenCode
  config. The evaluation harness, grader configuration, the rest of the host
  filesystem, and the user's home directory are physically unreachable.
- **No internet by default**, Softnet default-denies all egress
  (`--net-softnet-block=0.0.0.0/0`). A fully offline image (local models via
  Ollama) needs nothing more; for hosted models, open the provider's CIDR
  ranges with repeated `--vm-allow <CIDR>`.
- **SSH credentials** default to the Cirrus image convention (`admin`/`admin`);
  override with `--vm-user` / `--vm-password`.

**Boot sequence (TartOpenCodeAdapter):**

1. Verify `tart` and `sshpass` are on `PATH` (else `agentLaunchFailure`).
2. Write the hermetic `opencode.json` to a fresh `agent-config/` directory
   inside the run directory.
3. `tart run <image> --no-graphics --net-softnet --net-softnet-block=0.0.0.0/0
   [--net-softnet-allow=<cidrs>] --dir=workspace:<path> --dir=benchconfig:<path>:ro`
   in a long-running task.
4. Poll `tart ip <image> --wait 30` for up to 30s; fall back to 5s sleeps,
   fail after 30s.
5. Probe SSH with `ssh admin@<ip> true` every 5s; fail after 3 minutes.
6. SSH into the guest, `cd` into the workspace, set `OPENCODE_CONFIG` to the
   read-only mount's path, forward any allowlisted host variables, and run the
   same `opencode run --format json --pure --auto …` line.
7. On `cleanup`, run `tart stop <image>` and cancel the long-running `tart
   run` task as a backstop.

**Telemetry capability:** `structured`, identical to `opencode`.

### `fake`, pipeline smoke test

A no-op agent: it records a synthetic `agent_output` event, runs an
injectable actions closure (default: no-op), and exits 0. Used for two things:

1. **Pipeline self-test.** A `swift run applebench run runtime-002 --agent fake`
   exercises the full runner (environment validation → workspace clone →
   agent phase → diff capture → independent grading) without spending any
   tokens. A sound fixture must **FAIL** here, because the agent changed
   nothing and the planted defect is still present.
2. **Unit-test fixture.** `BenchmarkRunnerTests` uses a `ScriptedAdapter`
   modeled on `FakeAgentAdapter` to drive the runner through every state
   machine path (success, timeout, prepare failure, no-graders rejection,
   metadata-deferred-until-after-agent, etc.) without touching Xcode.

**Telemetry capability:** `plainText`, no structured events.

### `solution`, fixture self-check

Applies a fixture's reference solution patch and exits. **Not a benchmark
result and never appears in a comparison.** Exists so the harness can prove
the other half of a fixture's contract: a fixture is only meaningful if it
FAILs with an agent that changes nothing and PASSes with the known fix.

The patch lives outside the agent's checkout, under
`.applebench/solutions/<Fixture>.patch`, so the solution is never visible to
a real agent working in the workspace. The adapter derives the fixture name
from the trailing path component of `task.repository.url` (matching
`prepare-fixtures.sh`'s `./.applebench/fixtures/<Fixture>` layout), runs
`git apply --verbose --whitespace=nowarn` with a 120s timeout, and throws
`agentLaunchFailure` if the patch no longer applies, a drift between
fixture and recorded solution is treated as an authoring defect, not a
benchmark FAIL.

**Telemetry capability:** `plainText`, no structured events.

### Adding an agent harness

The `AgentAdapter` seam remains the extension point (a future FlowDeck
adapter, for instance):

1. Implement `AgentAdapter` (four methods) in `Sources/AppleBenchAgents/`.
2. Register it in `AgentCatalog.defaultRegistry()`.
3. Optionally implement `AgentOutputParser` if the CLI has structured output.

No core runner code changes.

