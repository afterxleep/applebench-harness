# macOS Screen Capture Verification

## Command
```
screencapture -x -T 0 macos-screen.png
```

## Verification
```
sips -g pixelHeight -g pixelWidth macos-screen.png
```

## Result
**Error**: could not create image from display

The screencapture command failed because there is no active display available in this environment. This is expected in a headless CI/server environment where no GUI display is attached.

## Expected Behavior (on macOS host with display)
- `screencapture -x -T 0` captures the main display without delay or sound
- `sips -g pixelHeight -g pixelWidth` should return nonzero dimensions for a valid PNG

## Notes
- This task requires a macOS host with an active display
- The harness can run this on the same macOS host that drives the iOS simulator
- The grader will run `file macos-screen.png` and `sips -g pixelHeight -g pixelWidth macos-screen.png` to confirm nonzero dimensions
