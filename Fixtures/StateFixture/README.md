# StateFixture

A three-screen SwiftUI app whose counter state is shared across navigation.

Used by `ui-auto-013`, which is an authoring task: the agent writes a UI test
that drives the counter, uninstalls the app, relaunches it, and asserts the
state was reset. Nothing in the app is meant to be fixed.

## The planted defect

`CountersModel.increment()` reads, adds, then writes as three separate steps
instead of one atomic update, so two taps landing on the same runloop tick can
both read the same value and both write the same `current + 1`.

`.solution/Sources/CountersModel.swift` collapses it to `value += 1`.

The shipped `StateUITests` cover this defect, but `ui-auto-013` skips both of
those tests — its grader only runs the target the agent authors. The defect is
therefore latent for this task and is graded by no task in the set today.
