# AssetCatalogFixture

An app whose badge artwork never appears. `Resources/Assets.xcassets` contains a
perfectly good `loom-badge` image set, but the catalog is excluded from the app
target — so it is never compiled, no `Assets.car` reaches the bundle, and
`UIImage(named: "loom-badge")` returns nil at runtime.

The build is clean and the code is correct; only the packaging is wrong. The
task grades this by what the built product actually contains, not by the text
of `project.pbxproj`.

`project.solution.yml` is the corrected XcodeGen spec the reference patch is
generated from.
