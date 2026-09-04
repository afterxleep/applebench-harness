# simctl Extra Commands Report

## Step 1: Set Location to Apple Headquarters
**Command:**
```bash
xcrun simctl location D036EE54-407B-400A-A92F-095492B46744 set 37.3349,-122.0090
```
- **Exit Code:** 0

## Step 2: Add Test Image to Photo Library
**Command:**
```bash
xcrun simctl addmedia D036EE54-407B-400A-A92F-095492B46744 /tmp/test_image.png
```
- **Exit Code:** 0

## Step 3: Start Video Recording
**Command:**
```bash
xcrun simctl io D036EE54-407B-400A-A92F-095492B46744 recordVideo --force /Users/afterxleep/Developer/applebench-harness/recording.mp4
```
- **Recording Duration:** 3 seconds
- **Signal sent:** SIGINT to stop recording

## Step 4: Output File
- **File:** `recording.mp4`
- **Size:** 120172 bytes (~117 KB)
