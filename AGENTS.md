# AGENTS.md

## Project Overview
NexusRelay Mobile contains native mobile clients for the external NexusRelay backend: `android/pixel` is a Kotlin/Jetpack Compose receiver that downloads backend device-sync jobs into Android MediaStore, and `ios/iphone` is a SwiftUI uploader that sends Apple Photos media to NexusRelay upload APIs. Backend and web source are not in this repo; API contracts live under `docs/contracts`.

## Setup Commands
```bash
# Android: JDK 17+, Android SDK target API 36
cd android/pixel

# iOS: macOS + Xcode + XcodeGen
cd ios/iphone
xcodegen generate --spec project.yml
```

## Run Commands
```bash
cd android/pixel
./gradlew.bat assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk

cd ios/iphone
xcodegen generate --spec project.yml
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Test Commands
```bash
cd android/pixel
./gradlew.bat testDebugUnitTest
./gradlew.bat connectedDebugAndroidTest

cd ios/iphone
xcodegen generate --spec project.yml
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Build / Lint / Format
```bash
cd android/pixel
./gradlew.bat assembleDebug

cd ios/iphone
xcodegen generate --spec project.yml
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```
⚠️ Undocumented — verify: no dedicated lint or format command was found.

## Repository Map
| Area | Path | Notes |
|---|---|---|
| Android Pixel app | `android/pixel` | Kotlin, Gradle, Compose, Retrofit, WorkManager, FCM, DataStore, MediaStore. |
| iPhone app | `ios/iphone` | Swift, SwiftUI, XcodeGen, PhotoKit, Keychain, SQLite, URLSession, BGProcessing. |
| Shared contracts | `docs/contracts` | Manually maintained API contracts consumed by mobile clients and implemented elsewhere. |
| Architecture docs | `docs/architecture` | Source notes for Pixel receiver and iPhone uploader flows. |
| CI/CD | `.github/workflows` | iOS CI and unsigned release artifact workflows only. |

## Codex Context Index
Read `.codex/context/index.md` first. It points to focused context files for architecture, mobile apps, contracts, persistence, integrations, messaging, security, CI/deployment, testing, and generated/off-limits areas.

## Working Rules
- Keep mobile changes scoped to the relevant platform unless a contract change requires both.
- Treat `docs/contracts` as the mobile/backend agreement and update tests when DTOs change.
- Do not run migrations, deploys, cleanup scripts, or external backend patch helpers unless explicitly requested.
- Do not print, copy, or commit real tokens, cookies, `google-services.json`, signing keys, provisioning profiles, or local device data.
- Preserve existing uncommitted user changes; this repo may have active Android, iOS, and contract work in progress.

## Generated / Do Not Edit
| Path | Source of truth | Regenerate command |
|---|---|---|
| `ios/iphone/NexusRelayIPhone.xcodeproj` | `ios/iphone/project.yml` | `cd ios/iphone && xcodegen generate --spec project.yml` |
| `android/pixel/app/build/` | Gradle | `cd android/pixel && ./gradlew.bat assembleDebug` |
| `artifacts/` | Local/generated outputs | ⚠️ Undocumented — verify |
| `window_dump.xml` | Captured Android UI dump | ⚠️ Undocumented — verify |

## Verification Before Completion
Run the smallest relevant checks first: Android DTO/sync changes should run focused Gradle unit tests, iOS API/ledger/upload changes should run focused `xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:<test-target>` tests on macOS, and contract-only changes should be reviewed against both mobile clients. If a check is unavailable on the current machine, state exactly what was not run.
