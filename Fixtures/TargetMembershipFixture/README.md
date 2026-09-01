# TargetMembershipFixture

An app that will not compile because one of its source files is not a member of
the app target. `ReadingsView` calls `ReadingFormatter.format(_:)`, and
`Sources/ReadingFormatter.swift` sits right there next to it in the repository,
but it is excluded from the target's sources — so the compiler reports it as an
unknown name.

The defect is in the project's configuration, not in any line of Swift. It is
graded by consequence: once the file really is a member of the target, the app
builds.

`project.solution.yml` is the corrected XcodeGen spec the reference patch is
generated from.
