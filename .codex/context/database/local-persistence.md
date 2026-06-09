---
scope: database/local-persistence
status: verified
sources:
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/AppSettingsStore.kt
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/LocalSyncLedger.kt
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/auth/DeviceTokenStore.kt
  - ios/iphone/NexusRelayIPhone/Core/Ledger/SQLiteUploadLedger.swift
  - ios/iphone/NexusRelayIPhone/Core/Utilities/SettingsStore.swift
  - ios/iphone/NexusRelayIPhone/Core/Auth/CookieSessionStore.swift
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# Local Persistence

## Android Persistence
| Store | Path | Data | Notes |
|---|---|---|---|
| DataStore `app_settings` | `AppSettingsStore.kt` | backend URL, target id, device name, Wi-Fi, FCM token, sync scope, auto-delete settings | Non-secret preferences. |
| DataStore `sync_ledger` | `LocalSyncLedger.kt` | JSON map of `LocalSyncRecord` keyed by job id | MVP local ledger; no migration tooling found. |
| EncryptedSharedPreferences `secure_device_prefs` | `DeviceTokenStore.kt` | raw device token | Uses AndroidX Security `MasterKey` and AES schemes. |
| Android MediaStore | `MediaStoreImporter.kt` | imported media files | Images/videos in NexusRelay folders, pending row during writes. |

## Android Ledger States
| State | Meaning | Public projection |
|---|---|---|
| `Queued` | job discovered locally | `Pending` |
| `Downloading` | backend marked downloading / local download active | `Syncing` |
| `Imported` | imported locally but not confirmed | `Syncing` |
| `ConfirmPending` | confirmation needs retry | `Syncing` |
| `Confirmed` | backend confirmed | `Synced` |
| `Failed` | terminal local failure | `Failed` |

## iOS Persistence
| Store | Path | Data | Notes |
|---|---|---|---|
| SQLite `ledger.sqlite` | `SQLiteUploadLedger.swift` | `upload_ledger` queue table | Created under app documents directory by view model/app delegate. |
| UserDefaults | `SettingsStore.swift` | backend URL, folder id/name, Wi-Fi, include videos/live-photo video | Non-secret settings. |
| Keychain | `CookieSessionStore.swift`, `KeychainStore.swift` | encoded cookie session | Service `com.nexusrelay.iphone.session`; accessible after first unlock. |
| Temporary files | `TemporaryFileStore.swift`, `ChunkFileBuilder.swift` | staged exports and chunks | App-private temp directories; cleanup implemented. |

## iOS SQLite Schema
| Column | Purpose |
|---|---|
| `id` | Primary key from asset id, resource kind, fingerprint, folder id. |
| `asset_local_identifier` | PhotoKit asset id; local only. |
| `resource_kind` | image, video, or livePhotoVideo. |
| `fingerprint_suffix` | first 16 hex chars of deterministic fingerprint. |
| `original_filename`, `uploaded_file_name`, `mime_type`, `size_bytes` | upload metadata. |
| `status` | persistent upload ledger state. |
| `backend_folder_id`, `backend_upload_id` | backend references. |
| `local_staged_file_url` | temporary export path. |
| `attempt_count`, `last_attempt_at`, `last_error` | retry and diagnostics. |

## Migration / Transaction Notes
| Area | Verified behavior | Gap |
|---|---|---|
| Android ledger | JSON blob read/write through DataStore edit calls | ⚠️ Undocumented — verify: no schema version or migration path found |
| iOS SQLite | `CREATE TABLE IF NOT EXISTS`, WAL mode, busy timeout, explicit transactions for bulk upsert/reconciliation | ⚠️ Undocumented — verify: no formal migration version table found |
| Backend DB | Not present in repo | ⚠️ Undocumented — verify in external backend repo |

## Change Safely
| Change | Files to inspect | Verification |
|---|---|---|
| Android ledger field/state | `LocalSyncLedger.kt`, sync repository, storage tests | `./gradlew.bat testDebugUnitTest --tests "com.nexusrelay.pixel.storage.*"` |
| Android token/settings | `DeviceTokenStore.kt`, `AppSettingsStore.kt`, setup/status UI | token/settings tests if present plus manual pair/unpair |
| iOS ledger schema/state | `SQLiteUploadLedger.swift`, ledger tests, queue/status models | `cd ios/iphone && xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:NexusRelayIPhoneTests/SQLiteUploadLedgerTests` |
| iOS session/settings | `CookieSessionStore.swift`, `SettingsStore.swift`, auth/setup tests | auth/setup XCTest targets |
