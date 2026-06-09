---
scope: architecture/service-map
status: partial
sources:
  - README.md
  - android/pixel/settings.gradle.kts
  - android/pixel/app/build.gradle.kts
  - ios/iphone/project.yml
  - .github/workflows/ios-iphone-ci.yml
  - .github/workflows/ios-iphone-release.yml
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# Service Map

## Deployable / Buildable Units
| Unit | Path | Runtime | Port | Owns DB? | Calls | Called by | Notes |
|---|---|---|---|---|---|---|---|
| Pixel companion app | `android/pixel` | Kotlin, Android Gradle Plugin 9.0.1, minSdk 29, target/compile SDK 36 | n/a | Local DataStore ledger/settings only | NexusRelay backend, FCM, Android MediaStore | User, FCM, WorkManager polling | Receiver device app. |
| iPhone uploader app | `ios/iphone` | Swift 5.10, iOS 17 target, XcodeGen | n/a | Local SQLite ledger, UserDefaults, Keychain | NexusRelay backend, Google OAuth, PhotoKit | User, BGProcessing | Uploader app. |
| NexusRelay backend | outside repo | ⚠️ Undocumented — verify | ⚠️ Undocumented — verify | Backend DB outside repo | Google Drive, FCM, auth provider | Pixel and iPhone apps | Referenced by contracts only. |

## Local Commands By Unit
| Unit | Build | Test | Release / Artifact |
|---|---|---|---|
| Pixel companion app | `cd android/pixel && ./gradlew.bat assembleDebug` | `./gradlew.bat testDebugUnitTest`; `./gradlew.bat connectedDebugAndroidTest` | ⚠️ Undocumented — verify: README documents debug APK install only |
| iPhone uploader app | `cd ios/iphone && xcodegen generate --spec project.yml && xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build` | `xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test` | `.github/workflows/ios-iphone-release.yml` builds simulator `.app` zip and unsigned device `.xcarchive` |

## Boundaries
| Boundary | Rule | Source |
|---|---|---|
| Mobile to backend | Mobile clients call NexusRelay backend APIs only | `README.md`, `docs/contracts/*.md` |
| Mobile to Google Drive | Mobile apps must not call Google Drive directly | `docs/architecture/*.md`, `docs/contracts/*.md` |
| Pixel queue | FCM is a wake-up signal; backend pending jobs are the durable queue | `docs/architecture/pixel-companion-sync.md` |
| iPhone queue | SQLite ledger is the local progress source; backend folder media supports reconciliation | `docs/architecture/iphone-photos-uploader.md` |

## Gaps / Verify
> ⚠️ Undocumented — verify: no CODEOWNERS, module ownership, Android CI, production mobile signing, backend service map, or cloud resource map was found.
