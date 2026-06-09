---
scope: testing/verification-matrix
status: partial
sources:
  - android/pixel/README.md
  - ios/iphone/README.md
  - .github/workflows/ios-iphone-ci.yml
  - ios/iphone/docs/manual-verification.md
  - docs/implementation/pixel-manual-verification.md
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# Verification Matrix

## Commands
| Area | Minimal checks | Broader checks | Notes |
|---|---|---|---|
| Android DTO/API contract | `cd android/pixel && ./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.api.*"` | `./gradlew.bat testDebugUnitTest` | Use when editing Retrofit DTOs/routes/statuses. |
| Android sync/ledger | focused `sync`, `storage`, or `ui` unit tests | `./gradlew.bat testDebugUnitTest` | Add manual sync if backend behavior changes. |
| Android MediaStore | relevant unit tests plus review | `./gradlew.bat connectedDebugAndroidTest` | Requires emulator/device. |
| Android debug build | `./gradlew.bat assembleDebug` | install with `adb install -r app/build/outputs/apk/debug/app-debug.apk` | FCM requires local `google-services.json`. |
| iOS API/auth | `xcodegen generate --spec project.yml && xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/NexusRelayAPIClientTests` | `xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test` | Requires macOS/Xcode. |
| iOS ledger/upload | focused ledger/upload XCTest targets | full CI-equivalent test/build | Requires macOS/Xcode. |
| iOS build | `xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build` | CI workflow on `macos-15` | Current Windows shell cannot run this. |
| Contract docs only | review both mobile API clients and tests | run affected Android/iOS DTO tests | Backend verification requires external repo/environment. |
| CI workflows | YAML review | GitHub Actions run | iOS workflows only. |

## Test Inventory
| Platform | Test paths |
|---|---|
| Android unit | `android/pixel/app/src/test/java/com/nexusrelay/pixel/**` |
| Android instrumented | `android/pixel/app/src/androidTest/java/com/nexusrelay/pixel/**` |
| iOS unit | `ios/iphone/NexusRelayIPhoneTests/**` |
| Manual Pixel | `docs/implementation/pixel-manual-verification.md` |
| Manual iPhone | `ios/iphone/docs/manual-verification.md` |

## Manual Verification Triggers
| Change | Manual check |
|---|---|
| Pairing/device token | Pair Pixel against local/staging backend and verify backend target. |
| FCM | Provide `google-services.json`, background app, confirm push wakes sync. |
| Polling fallback | Disable/remove FCM config and wait for 15-minute poll. |
| iPhone Photos permissions | Test full and limited access on simulator/device. |
| iCloud assets/background upload | Physical iPhone recommended. |
| Cross-app relay | Upload from iPhone, confirm backend completion, verify Pixel receives/imports. |

## Gaps / Verify
> ⚠️ Undocumented — verify: no Android CI gate, no automated end-to-end contract test against the backend, and no load/performance test suite were found.
