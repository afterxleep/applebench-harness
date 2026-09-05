# simctl Extra Steps Report

## Step 1: Set Location to Apple Headquarters
**Command:** `xcrun simctl location booted set 37.3349,-122.0090`

**Exit Code:** 0

**Output:** (no output)

---

## Step 2: Add Test Image to Photo Library
**Command:** `xcrun simctl addmedia booted /tmp/test_image.jpg`

**Exit Code:** 0

**Output:** (no output)

---

## Step 3 & 4: Video Recording (Start and Stop after 3 seconds)
**Start Command:** `xcrun simctl io booted recordVideo --force recording.mp4`

**Stop:** SIGINT (kill -INT) after 3 seconds

**Exit Code:** 0

**Output:**
```
Note: No display specified. Defaulting to display: F3B7A077-4ADD-443A-B945-EB603904E003 (screenID: 1, name: LCD)
Recording started
Recording completed. Writing to disk.
Wrote video to: /Users/afterxleep/Developer/applebench-harness/recording.mp4
```

**Recording File Size:** 16,285 bytes

---

## Notes
- Simulator: iPhone 17 (iOS 26.5) - Already booted
- Test image: /tmp/test_image.jpg (100x100 JPEG)
- Location set to Apple HQ: 37.3349, -122.0090
