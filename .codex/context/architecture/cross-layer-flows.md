---
scope: architecture/cross-layer-flows
status: partial
sources:
  - docs/architecture/pixel-companion-sync.md
  - docs/architecture/iphone-photos-uploader.md
  - docs/contracts/device-sync-api.md
  - docs/contracts/iphone-upload-api.md
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/DeviceSyncRepository.kt
  - ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# Cross-Layer Flows

## Pixel Pairing And Receive Sync
| Step | Layer | Path | Notes |
|---|---|---|---|
| 1 | Android setup UI | `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/SetupScreen.kt` | User enters backend URL, pairing code, device name, Wi-Fi preference. |
| 2 | FCM token resolution | `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/FcmTokenResolver.kt`, `sync/FcmTokenSync.kt` | Uses current or stored Firebase token. |
| 3 | API contract | `docs/contracts/device-sync-api.md` | `POST /api/device-sync/pairing-codes/redeem`. |
| 4 | Android API client | `android/pixel/app/src/main/java/com/nexusrelay/pixel/api/NexusRelayApi.kt` | Retrofit call returns target/device token/scope. |
| 5 | Local storage | `auth/DeviceTokenStore.kt`, `storage/AppSettingsStore.kt` | Device token stored encrypted; settings stored in DataStore. |
| 6 | Background execution | `sync/SyncWorker.kt`, `sync/PollWorker.kt`, `sync/FcmReceiverService.kt` | FCM and polling enqueue the same sync worker. |
| 7 | Sync repository | `sync/DeviceSyncRepository.kt` | Lists pending jobs, downloads, imports, confirms, retries confirmation. |
| 8 | Device media store | `media/MediaStoreImporter.kt` | Writes images to `Pictures/NexusRelay`, videos to `Movies/NexusRelay`. |

## iPhone Google Sign-In And Upload
| Step | Layer | Path | Notes |
|---|---|---|---|
| 1 | Setup UI/model | `ios/iphone/NexusRelayIPhone/Features/Setup/SetupViewModel.swift` | Saves server/settings, starts Google auth, resolves destination folder. |
| 2 | Browser auth | `Core/Auth/GoogleAuthCoordinator.swift`, `Core/Auth/AuthCallbackURL.swift` | Uses `ASWebAuthenticationSession` and `nexusrelay://` callback. |
| 3 | Session exchange | `Core/API/NexusRelayAPIClient.swift` | `POST api/auth/ios/session-exchange`; cookie session saved. |
| 4 | API auth transport | `Core/API/HTTPClient.swift`, `Core/Auth/CSRFTokenProvider.swift` | Adds CSRF for unsafe methods and refreshes once on 401. |
| 5 | Photo scan | `Core/Photos/PhotoKitPhotoLibraryClient.swift` | Uses public PhotoKit APIs for image/video candidates. |
| 6 | Local queue | `Core/Ledger/SQLiteUploadLedger.swift` | Upserts discovered candidates and state transitions. |
| 7 | Export and upload | `Core/Upload/SyncOrchestrator.swift`, `UploadEngine.swift` | Exports to temp files and streams/chunks to backend upload APIs. |
| 8 | Reconciliation | `Core/Upload/ReconciliationService.swift` | Lists folder media and marks local records synced by uploaded filename. |

## Cross-App Relay Flow
| Step | Source | Target | Contract |
|---|---|---|---|
| 1 | iPhone app uploads media to NexusRelay | External backend | `docs/contracts/iphone-upload-api.md` |
| 2 | Backend relays media and marks it completed | External Google Drive/backend DB | ⚠️ Undocumented — verify |
| 3 | Backend creates device sync jobs for Pixel targets | Pixel pending-jobs API | `docs/contracts/device-sync-api.md` |
| 4 | Pixel imports media and confirms completion | External backend | `POST /api/device-sync/jobs/{jobId}/confirm` |

## Gaps / Verify
> ⚠️ Undocumented — verify: backend handlers, database transactions, Google Drive relay completion, FCM sending, and web pairing-code creation are not traceable in this repo.
