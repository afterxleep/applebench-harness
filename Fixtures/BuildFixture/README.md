# BuildFixture

A tiny SwiftUI app that compiles cleanly. Used by operational tasks as a
working project to clean, build, sign, and list schemes against. The
Swift 6 isolation bug that used to live here was removed when language-level
Swift tasks were dropped from the set.

Generate the Xcode project with `xcodegen generate` (the AppleBench prepare
script does this for you).
