# Public harness, private gold

AppleBench splits in two so published scores stay honest.

## What is public

The harness: grading engine, task schema, fixture-generation tooling, and
the grader types (`build`, `xctest`, `xcuitest`, `runtime`, `file`,
`xcodeproj`). Plus a small **dev** subset of 8 tasks that is expected to
leak and is **never used for published scores**.

Export a publishable tree with:

```bash
./Scripts/export-public-tree.sh
```

The output under `dist/applebench-public/` contains no gold prompts,
no gold fixtures, and no gold `solution.patch` files.

## What stays private

Task prompts, fixtures, and expected outputs for the **gold** scoring set
(`Examples/Suites/gold.yaml`). Submissions run here, or through a hosted
eval endpoint. The gold set is never handed out.

Eval runs are sandboxed either way: no internet, no search, standard
Apple toolchain only. Closed gold stops pretraining contamination;
sandboxing stops in-run cheating. Both are required.

## Scores

Publish aggregate scores from `gold.yaml` only. `dev.yaml` is a demo.
`all-benchmark.yaml` is local verification and includes the leakable
subset: do not score it.

## Rotation

Fixtures are XcodeGen manifests with templated bugs. Periodically rotate
the private set so leaked transcripts do not remain a valid key:

```bash
./Scripts/rotate-private-set.sh 2026-q4
```

That is the long-term defense. Keeping gold private buys time; rotation
keeps the benchmark alive past year one.
