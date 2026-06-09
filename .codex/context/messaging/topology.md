---
scope: messaging/topology
status: partial
sources:
  - docs/architecture/pixel-companion-sync.md
  - docs/contracts/device-sync-api.md
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/FcmReceiverService.kt
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/SyncWorker.kt
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/sync/PollWorker.kt
  - ios/iphone/NexusRelayIPhone/App/AppDelegate.swift
  - ios/iphone/NexusRelayIPhone/Core/Background/BackgroundSyncScheduler.swift
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# Messaging And Background Topology

## Topology
| Topic/Queue | Producer | Consumer | Message | Delivery assumptions | Retry/DLQ |
|---|---|---|---|---|---|
| FCM data signal | NexusRelay backend outside repo | `FcmReceiverService` | `type=device_sync_job_available`, optional `jobId` | Signal only; backend pending jobs are durable queue | No DLQ in mobile repo; missed messages recovered by polling |
| WorkManager one-time sync | Setup UI, FCM receiver, PollWorker | `SyncWorker` | Work request named `nexus-relay-pixel-sync` | Unique work, `ExistingWorkPolicy.KEEP` | WorkManager exponential retry on `IOException` |
| WorkManager poll | MainActivity/setup schedules | `PollWorker` | Periodic request named `nexus-relay-pixel-poll` every 15 minutes | Connected network required | Poll enqueues one-time sync |
| iOS BGProcessing | App launch and scheduler | `AppDelegate`, `BackgroundSyncScheduler` | task id `com.nexusrelay.iphone.sync` | iOS best-effort background execution | Task rescheduled; expiration cancels work |

## Durable State Sources
| Flow | Durable source |
|---|---|
| Pixel backend queue | External NexusRelay backend pending jobs |
| Pixel local progress | Android DataStore `sync_ledger` |
| iPhone local upload queue | SQLite `upload_ledger` |
| iPhone backend reconciliation | Backend folder media filenames |

## Gaps / Verify
> ⚠️ Undocumented — verify: backend FCM send implementation, retry/DLQ/alerting for push delivery, and server-side durable queue schema are outside this repo.
