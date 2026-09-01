# Clean rebuild report — BuildFixture

Derived data before clean: 214M
Derived data after clean: 0B
Rebuild wall clock: 38.6s

Commands:

```
xcodebuild clean -project BuildFixture.xcodeproj -scheme BuildFixture
rm -rf ~/Library/Developer/Xcode/DerivedData/BuildFixture-*
xcodebuild -project BuildFixture.xcodeproj -scheme BuildFixture build
```
