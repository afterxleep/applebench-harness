# Simulator Lifecycle Report

**Date:** Wed Sep 02 2026
**Device Type:** iPhone 16
**Runtime:** iOS 18.6
**UDID:** 5BCE77F4-D0AF-46A7-A1C5-6C81FE482627

## Steps

| Step | Command | Exit Code | Wall-Clock Time |
|------|---------|-----------|-----------------|
| 1. Create | `xcrun simctl create opencode-lifecycle-test com.apple.CoreSimulator.SimDeviceType.iPhone-16 com.apple.CoreSimulator.SimRuntime.iOS-18-6` | 0 | 0.262s |
| 2. Boot | `xcrun simctl boot 5BCE77F4-D0AF-46A7-A1C5-6C81FE482627` | 0 | 1.841s |
| 3. Wait for Booted | Polling until status == Booted | 0 | 0.214s |
| 4. Erase (while Booted) | `xcrun simctl erase 5BCE77F4-D0AF-46A7-A1C5-6C81FE482627` | 149 | 0.150s |
| 5. Shutdown | `xcrun simctl shutdown 5BCE77F4-D0AF-46A7-A1C5-6C81FE482627` | 0 | 3.240s |
| 6. Erase (after Shutdown) | `xcrun simctl erase 5BCE77F4-D0AF-46A7-A1C5-6C81FE482627` | 0 | 0.198s |
| 7. Delete | `xcrun simctl delete 5BCE77F4-D0AF-46A7-A1C5-6C81FE482627` | 0 | 0.122s |

## Notes

- Step 4 (erase while booted) failed with error 405: "Unable to erase contents and settings in current state: Booted". The erase operation requires the device to be in Shutdown state.
- After issuing the shutdown command (Step 5), the erase was re-attempted and succeeded (Step 6).
