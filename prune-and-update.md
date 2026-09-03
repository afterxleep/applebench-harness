# Prune and Update Report

Generated: 2026-09-02T14:53:23Z

## Part A: Prune

Deleted the following simulators (Shutdown state, dataPath older than 1 hour):

| UDID | Name |
|------|------|
| 54DA1168-8044-4DFC-882C-BAC43741CB13 | DecodingFixtureFresh |
| 2223CA08-2145-43D4-BFAA-82EB0BD4539B | FormFlowTest |

**Note:** The benchmark's freshly-booted iPhone 17 / iOS 26.5 simulator (UDID: 7573C7AB-0864-4A9B-8E77-8BB2F8BB06FC, name: iPhone17-Test) was preserved as instructed.

## Part B: Upgrade

**Benchmark simulator:** 7573C7AB-0864-4A9B-8E77-8BB2F8BB06FC (iPhone17-Test)

**Current runtime:** iOS 26.5 (26.5 - 23F77)

**Available runtimes:**
- iOS 26.4 (26.4 - 23E244)
- iOS 26.5 (26.5 - 23F77) ← current

**Result:** No newer iOS runtime available. The benchmark simulator is already on the latest iOS 26.5 runtime.
