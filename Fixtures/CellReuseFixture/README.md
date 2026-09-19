# CellReuseFixture

A UIKit contacts list (wrapped in SwiftUI) where `ContactCell` starts an async
avatar load in `configure` and applies whatever image arrives — with no reuse
guard and no reset in `prepareForReuse` — so fast scrolling puts avatars on
the wrong rows. Used by the `reuse-001` task (build + XCTest graders).
Modeled on the cell-reuse / async-image exercises common in iOS engineering
interviews.

Generate the Xcode project with `xcodegen generate` (the AppleBench prepare
script does this for you).
