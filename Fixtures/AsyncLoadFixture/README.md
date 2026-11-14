# AsyncLoadFixture

A SwiftUI profile screen that crashes the moment it appears. `ProfileScreen`
force-unwraps `loader.profile` while building its body, but the profile is nil
until the `.task` that loads it finishes — so the very first body evaluation
traps.

Nothing about this is visible to the compiler; the app builds cleanly and only
fails when it runs.

The fix is to render the loading state honestly (`if let`) rather than assuming
the value is already there.

Generate the Xcode project with `xcodegen generate` (the AppleBench prepare
script does this for you).
