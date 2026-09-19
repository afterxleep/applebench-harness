# Repository conventions

## No repository history

This repository is public and keeps no history. `main` is always a single
root commit holding the latest version of the project. Earlier commits leaked
task solutions and internal details, and nothing may be recoverable from past
commits again.

Every change lands the same way:

1. Commit the change on `main` as usual.
2. Replace `main` with one parentless commit of the current tree, without
   switching branches:

   ```bash
   git update-ref refs/heads/main "$(git commit-tree HEAD^{tree} -m 'AppleBench harness')"
   ```

3. Force-push it: `git push --force origin main`.
4. Verify the remote holds exactly one commit and no other branches or tags:
   `git fetch --prune origin && git rev-list --count origin/main` prints `1`,
   and `git ls-remote origin` lists only `HEAD`, `refs/heads/main` and
   GitHub's read-only `refs/pull/*` refs.

Never push another branch or tag. A force-push to `main` that changes nothing
under `site/` does not trigger the Pages workflow; when `site/` changed, run
`gh workflow run pages.yml --ref main` if the deploy did not start.

## Published model names

Public reports identify the model, not the routing gateway. Strip a leading
`openrouter/` from every user-facing model name generated for the website.
Keep the complete provider-qualified identifier in machine-readable benchmark
exports because pricing, reproducibility, and reruns depend on it.

## Proving a task change

A task, fixture, reference solution, or grader change is not done until the
fail-then-pass check has run on every task it touches and come back `ok`:

```bash
APPLEBENCH_TASKSET=/path/to/task-set ./Scripts/verify-fixtures.sh <task-id> ...
```

The `fake` agent changes nothing and must FAIL; the `solution` agent applies
the reference fix and must PASS. `fake PASS` means the grader cannot tell a
solved task from an untouched one; `solution FAIL` means the task cannot be
solved or scored as written. Both are broken tasks, never results.

- A shared fixture change (a `.solution/` file, `project.solution.yml`, the
  starter sources) touches every task that uses that fixture, so verify all
  of them. Regenerate `solution.patch` with `./Scripts/make-solutions.sh
  <Fixture>` first.
- A harness grader change touches every task using that grader type: run
  `swift test` and verify a sample of those tasks.
- Verification takes a lock and owns its simulators. Never run it while a
  benchmark or another verification is running.
- Report the verdict table as it printed. Do not publish, re-date, or ask for
  model reruns of a task whose last verdict was not `ok`.
