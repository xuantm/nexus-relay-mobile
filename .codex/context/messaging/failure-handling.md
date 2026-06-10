---
scope: messaging/failure-handling
status: partial
sources:
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/DeviceSyncRepository.kt
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/SyncWorker.kt
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/LocalSyncLedger.kt
  - ios/iphone/NexusRelayIPhone/Core/Upload/SyncOrchestrator.swift
  - ios/iphone/NexusRelayIPhone/Core/Upload/UploadEngine.swift
  - ios/iphone/NexusRelayIPhone/Core/Upload/ReconciliationService.swift
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# Failure Handling

## Android Pixel
| Failure | Behavior | Source |
|---|---|---|
| Network/backend transient failure | `DeviceSyncRepository` throws/propagates as `IOException`; `SyncWorker` returns retry | `DeviceSyncRepository.kt`, `SyncWorker.kt` |
| Interrupted/stalled download | On next sync, records in `Downloading` older than 60 minutes become `Failed` and Pixel reports backend `/fail` so the job does not stay stuck in `Downloading` | `recoverInterruptedDownloads()` |
| Import succeeds but confirm fails | Record is kept `ConfirmPending`; later sync retries confirm before new jobs | `retryLocalConfirmation()` |
| Terminal job failure | Ledger marks failed, then app attempts backend `/fail` report | `DeviceSyncRepository.kt` |
| Duplicate prevention | Ledger skips `Confirmed` records and retries local confirmations without redownloading | `DeviceSyncRepository.kt`, `LocalSyncLedger.kt` |
| Local cleanup failure | Cleanup errors are logged but do not fail sync | `cleanUpLocalFiles()` |

## iOS iPhone
| Failure | Behavior | Source |
|---|---|---|
| Wi-Fi-only on cellular | Sync throws `cellularConnectionBlocked` | `SyncOrchestrator.swift` |
| Low Power Mode | Queue loop stops processing | `SyncOrchestrator.swift` |
| Export failure | Ledger marks failed with retryable flag based on error | `SyncOrchestrator.swift` |
| HTTP transient upload failure | `UploadEngine` retries up to policy max with exponential backoff | `UploadEngine.swift`, `UploadPolicy.swift` |
| HTTP 4xx non-401 | Treated as permanent by upload engine | `UploadEngine.isPermanentFailure()` |
| Auth 401 | HTTP client attempts refresh and retries once | `HTTPClient.swift` |
| Ledger corruption | Bad DB is moved aside and recreated | `LedgerFactory.createOrRecoverLedger` |
| Local ledger loss/corruption | Reconciliation lists backend folder media and marks matching uploaded filenames synced | `ReconciliationService.swift` |

## Gaps / Verify
> ⚠️ Undocumented — verify: no mobile alerting, metrics, DLQ replay, poison-message policy, backend retry policy, or server-side idempotency key documentation was found.
