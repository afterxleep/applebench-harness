# Run limits and safety

- The wall-clock timeout is enforced by AppleBench: on expiry the agent's
  entire process tree is terminated (the child runs in its own process group),
  the timeout is recorded, and grading still runs against whatever remains.
- Commands are spawned directly (`posix_spawn`), never through `sh -c`; task
  YAML is never interpolated into shell strings.
- Agents run with a minimal environment (`PATH`, `HOME`, and friends) plus an
  explicit allowlist (`--allow-env NAME`, repeatable). Unrelated secrets are
  not exposed by default.
- Agents are autonomous processes that can run arbitrary commands on this
  machine. v1 is trusted-local-machine tooling: run it on hardware you trust
  with checkouts you accept executing. Interfaces are designed so VM-based
  isolation can be added later.

