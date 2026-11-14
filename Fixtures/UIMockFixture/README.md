# UIMockFixture

A profile card screen that has drifted from its design reference
(`Design/expected-ui.png`): the screen title reads "profile card" instead of
"Profile", the bio sits above the name instead of below it, and the Follow
button is missing entirely.

The app builds and runs; only the layout is wrong.

The fix is to bring the screen back in line with the reference — correct title,
avatar, name, bio, Follow button, in that order.

Generate the Xcode project with `xcodegen generate` (the AppleBench prepare
script does this for you).
