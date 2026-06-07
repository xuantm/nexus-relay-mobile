# Pixel Companion Sync Architecture

## Goal

Build an Android Pixel companion app that receives media uploaded into NexusRelay, downloads it from the backend, imports it into Android MediaStore, and confirms completion.

The first mobile milestone is Pixel-only. iPhone uploader work should be planned separately after the Pixel receiver path is stable.

## Sync Scope

The backend is the source of truth for sync scope. Pixel never receives all jobs and filters locally. DeviceSyncService creates jobs only for targets whose account and scope match the completed media item.

## Recommended Design

Use:

```text
FCM signal + WorkManager pull + polling fallback
```

NexusRelay should not push full files to the phone. The backend creates a durable job and sends a small FCM data message. The app uses WorkManager to fetch pending jobs and download media through backend APIs. Periodic polling recovers missed FCM events.

## Flow

```text
Browser upload into NexusRelay
  -> backend relays media to Google Drive
  -> MediaItem becomes Completed
  -> backend creates DeviceSyncJob
  -> backend sends FCM job-available signal
  -> Pixel app receives FCM
  -> Pixel app enqueues WorkManager sync
  -> Pixel app lists pending jobs
  -> Pixel app downloads media over HTTPS
  -> Pixel app writes to MediaStore with IS_PENDING
  -> Pixel app confirms ImportedConfirmed
```

## Components

### Setup UI

The app needs a small setup flow:

- backend base URL;
- device name;
- temporary pairing code or QR code;
- Wi-Fi only toggle;
- registration status;
- manual sync button.

### API Client

The app talks only to NexusRelay backend endpoints documented in `docs/contracts/device-sync-api.md`.

The app sends `X-Device-Token` for device job endpoints. It stores the device token in encrypted local storage.

### FCM Receiver

The receiver handles `device_sync_job_available` and enqueues sync work. The FCM payload contains only a job id and routing type. It does not contain download URLs, auth tokens, Google Drive ids, or media metadata beyond the job id.

> [!NOTE]
> FCM token refresh/rotation is handled automatically. Rotated FCM tokens are updated on the backend using the device token via the FCM token update endpoint (`POST /api/device-sync/fcm-token`). Device registration is performed anonymously using a pairing code, meaning user credentials are never stored or managed on the device.

### WorkManager Sync

WorkManager is the durable background executor:

- fetch pending jobs;
- mark each job as downloading;
- stream download into temporary app-private storage;
- import to MediaStore;
- confirm to backend;
- retry network failures with backoff.

Default constraints:

```text
Network connected
Storage not low
Battery not low
```

If Wi-Fi only is enabled, require an unmetered network.

### Polling Fallback

FCM is not the queue. The durable queue is the backend database.

Schedule periodic polling every 15 minutes. Polling should run the same sync path as FCM-triggered sync.

### Local Ledger

The app keeps a local sync ledger so it can resume after process death, reboot, network drop, or confirm failure.

Record shape:

```text
jobId
mediaId
fileName
mimeType
sizeBytes
sha256
status
localUri
lastAttemptAt
lastError
```

If media import succeeds but backend confirmation fails, store `localUri` and retry confirmation later.

### MediaStore Import

Images:

```text
Pictures/NexusRelay
```

Videos:

```text
Movies/NexusRelay
```

Use `IS_PENDING=1` while writing and update to `IS_PENDING=0` only after the full stream is written and verified.

## Security

- The app never calls Google Drive directly.
- The app never stores the user's password.
- The device token is revocable and scoped to device sync APIs.
- The FCM payload contains no secrets.
- Backend download endpoints validate job ownership through the device token.

## Recovery

The app should recover from:

- missed FCM messages through polling;
- failed downloads through WorkManager retry;
- confirm failures through local ledger retry;
- app restarts through persisted token and ledger;
- backend downtime through retry and manual sync.

## Release Strategy

MVP can be distributed as a sideloaded debug or internal release APK. Play Store distribution is not required for the first validation.

