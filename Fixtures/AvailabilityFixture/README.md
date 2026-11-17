# AvailabilityFixture

A SwiftUI app that does not compile: `LibraryView` places a toolbar item with
`ToolbarItemPlacement.subtitle`, which is only available from iOS 26.0, while
the project deploys to iOS 18.0.

The planted defect is the unguarded use of a newer API, not the deployment
target. Raising `IPHONEOS_DEPLOYMENT_TARGET` would silence the compiler while
dropping every iOS 18 device, so the `build-002` task pins the deployment
target with an `xcodeproj` grader. The fix is an `if #available(iOS 26.0, *)`
guard so the subtitle appears where it is supported and is simply absent
elsewhere.

Generate the Xcode project with `xcodegen generate` (the AppleBench prepare
script does this for you).
