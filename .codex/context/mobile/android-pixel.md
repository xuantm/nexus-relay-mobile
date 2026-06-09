---
scope: mobile/android-pixel
status: verified
sources:
  - android/pixel/README.md
  - android/pixel/settings.gradle.kts
  - android/pixel/app/build.gradle.kts
  - android/pixel/app/src/main/AndroidManifest.xml
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/MainActivity.kt
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/api/NexusRelayApi.kt
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/DeviceSyncRepository.kt
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# Android Pixel App

## Summary
| Item | Value |
|---|---|
| Path | `android/pixel` |
| Runtime | Kotlin, Gradle Kotlin DSL, Android Gradle Plugin 9.0.1 |
| App id | `com.nexusrelay.pixel` |
| SDKs | min 29, target/compile 36 |
| UI | Jetpack Compose Material 3 |
| Network | Retrofit, OkHttp, Moshi |
| Background | WorkManager, Firebase Cloud Messaging, 15-minute polling fallback |
| Local state | DataStore Preferences, EncryptedSharedPreferences |

## Folder Structure
| Path | Purpose |
|---|---|
| `app/src/main/java/com/nexusrelay/pixel/api` | Retrofit interface, DTOs, API client factory, pairing-code parser. |
| `app/src/main/java/com/nexusrelay/pixel/auth` | Encrypted device-token storage. |
| `app/src/main/java/com/nexusrelay/pixel/storage` | DataStore app settings and local sync ledger. |
| `app/src/main/java/com/nexusrelay/pixel/sync` | Device sync repository, WorkManager workers, FCM receiver/token sync. |
| `app/src/main/java/com/nexusrelay/pixel/media` | Android MediaStore import. |
| `app/src/main/java/com/nexusrelay/pixel/ui` | Compose setup, status, settings, ledger UI models/components. |
| `app/src/test/java/com/nexusrelay/pixel` | Unit tests for DTOs, ledger, sync repository, UI models. |
| `app/src/androidTest/java/com/nexusrelay/pixel` | Instrumented MediaStore importer test. |

## Canonical Facts
| Fact | Source |
|---|---|
| Release builds default to `https://relay.xuantruong.org`; debug shows backend URL field. | `android/pixel/README.md`, `app/build.gradle.kts` |
| Pairing uses `POST api/device-sync/pairing-codes/redeem`. | `api/NexusRelayApi.kt`, `api/DeviceSyncDtos.kt` |
| Device sync endpoints use `X-Device-Token`. | `api/NexusRelayApi.kt`, `docs/contracts/device-sync-api.md` |
| FCM receiver only reacts to `type=device_sync_job_available` and enqueues sync. | `sync/FcmReceiverService.kt` |
| Periodic fallback is a 15-minute WorkManager poll. | `sync/PollWorker.kt` |
| Media import uses `IS_PENDING` and writes images/videos to NexusRelay folders. | `media/MediaStoreImporter.kt` |

## Change Safely
| Change | Inspect | Verification |
|---|---|---|
| API DTO or route | `api/*`, `docs/contracts/device-sync-api.md`, DTO tests | `cd android/pixel && ./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.api.*"` |
| Sync behavior | `sync/DeviceSyncRepository.kt`, `storage/LocalSyncLedger.kt`, sync tests | `./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.sync.*"` |
| Ledger/state labels | `storage/LocalSyncLedger.kt`, `ui/PixelUiModels.kt`, tests | `./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.storage.*" --tests "com.nexusrelay.pixel.ui.*"` |
| Media import | `media/MediaStoreImporter.kt`, manifest permissions, androidTest | `./gradlew.bat connectedDebugAndroidTest` |
| FCM/polling | `sync/FcmReceiverService.kt`, `sync/FcmTokenSync.kt`, `sync/PollWorker.kt` | manual device/emulator verification with/without `google-services.json` |

## Gaps / Verify
> ⚠️ Undocumented — verify: Android CI workflow and release signing pipeline were not found.

> ⚠️ Undocumented — verify: `google-services.json` must be supplied locally for FCM but is intentionally ignored.
