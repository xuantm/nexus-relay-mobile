# Device Sync API Contract

This contract is consumed by the Pixel companion app and implemented by the NexusRelay backend.

## Auth

Device job endpoints use a revocable device token:

```text
X-Device-Token: <device-token>
```

The backend stores only a hash of the device token. The raw token is returned once during registration and stored on the Pixel with encrypted storage.

Device registration is performed anonymously using a temporary pairing code created in an authenticated web session:

```text
POST /api/device-sync/pairing-codes/redeem
```

## Endpoints

### Redeem Pairing Code

```http
POST /api/device-sync/pairing-codes/redeem
Content-Type: application/json
```

Request:

```json
{
  "code": "12345678",
  "deviceName": "Pixel XL",
  "platform": "Android",
  "fcmToken": "fcm-token-from-firebase"
}
```

Response:

```json
{
  "targetId": "4d6b0f2e-47b6-49fd-8daa-c87e70307f9f",
  "deviceToken": "raw-device-token-returned-once",
  "syncScope": "Folder",
  "scopedFolderId": "2f1cbb66-4a8d-4d62-b14d-67d821742958",
  "wifiOnly": true
}
```

Allowed syncScope values:
- AccountUploads: sync completed media uploaded by the registering account.
- Folder: sync completed media uploaded by the registering account only when the media belongs to scopedFolderId.

### List Pending Jobs

```http
GET /api/device-sync/jobs/pending
X-Device-Token: <device-token>
```

Response:

```json
[
  {
    "jobId": "8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef",
    "mediaId": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1",
    "fileName": "IMG_1001.HEIC",
    "mimeType": "image/heic",
    "mediaType": "Image",
    "sizeBytes": 4820131,
    "sha256": "3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7",
    "downloadUrl": "/api/device-sync/jobs/8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef/download",
    "createdAt": "2026-06-02T00:00:00Z",
    "status": "Pending"
  }
]
```

### Mark Downloading

```http
POST /api/device-sync/jobs/{jobId}/downloading
X-Device-Token: <device-token>
```

Expected response:

```text
204 No Content
```

### Download Job Media

```http
GET /api/device-sync/jobs/{jobId}/download
X-Device-Token: <device-token>
```

Expected response:

```text
200 OK
Content-Type: image/heic | image/jpeg | video/mp4 | application/octet-stream
Content-Disposition: attachment; filename="<safe-file-name>"
```

The response streams bytes from the NexusRelay backend. The Pixel app must not call Google Drive directly.

### Confirm Import

```http
POST /api/device-sync/jobs/{jobId}/confirm
X-Device-Token: <device-token>
Content-Type: application/json
```

Request:

```json
{
  "importedUri": "content://media/external/images/media/12345",
  "importedSizeBytes": 4820131
}
```

Expected response:

```text
204 No Content
```

The backend marks the job as `ImportedConfirmed`.

### Report Failure

```http
POST /api/device-sync/jobs/{jobId}/fail
X-Device-Token: <device-token>
Content-Type: application/json
```

Request:

```json
{
  "error": "Network disconnected during download"
}
```

Expected response:

```text
204 No Content
```

The Pixel client must treat any terminal local failure as a backend-visible failure. If the client marks a job `Failed`, it must also call this endpoint rather than only updating local counters or ledger state.

The endpoint must be idempotent for the same device/job/error. Pixel stores whether a local failed record has been successfully reported to the backend; if reporting fails because the network or backend is unavailable, Pixel will retry `POST /fail` on later sync cycles until the backend acknowledges it.

Backend retry/cancel tooling should use this backend-visible failed state as the point where an operator or automatic policy can create a fresh pending attempt. Retrying should not reuse a stale `Downloading` attempt forever.

## FCM Payload

FCM is a signal, not a file transport.

```json
{
  "type": "device_sync_job_available",
  "jobId": "8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef"
}
```

The Pixel app should enqueue sync work after receiving this message, then call `GET /api/device-sync/jobs/pending`. The app should not trust FCM as the durable queue.

Backend should send Android FCM sync signals as high-priority data messages only when a user-visible or time-sensitive device sync should run promptly. If FCM reports deleted messages to the Pixel app, Pixel enqueues a full sync and reconciles from `GET /api/device-sync/jobs/pending`; backend pending jobs remain the durable source of truth.

## Status Vocabulary

Shared API status values:

```text
Pending
Syncing
Synced
Failed
```

Backend job states are projected into the shared API `status` field above. The Pixel app should treat `Pending` as queued work, `Syncing` as active transfer or confirmation work, `Synced` as completed, and `Failed` as terminal failure.

Pixel local statuses remain internal:

```text
Queued
Downloading
Imported
ConfirmPending
Confirmed
Failed
```

Pixel maps local states to the shared API vocabulary as follows:

- Queued -> Pending
- Downloading -> Syncing
- Imported -> Syncing
- ConfirmPending -> Syncing
- Confirmed -> Synced
- Failed -> Failed

## Stalled Job Handling

`Downloading` is not allowed to remain open-ended.

- Pixel should treat a local `Downloading` record older than 60 minutes as stalled.
- When that happens, Pixel must mark the local record `Failed` and call `POST /api/device-sync/jobs/{jobId}/fail`.
- The backend should treat `Downloading` jobs older than 30-60 minutes as stalled as well, move them out of the active bucket, and make retry or cancel actions explicit in operator tooling.
- Retry should create a fresh pending attempt. Cancel should leave a terminal failed/cancelled record instead of keeping the job in `Downloading`.

## Counter Alignment

For dashboard parity, use the same completion definition on both sides:

- Backend completion source of truth: `ImportedConfirmed`
- Pixel completion source of truth: local `Confirmed`, meaning `/confirm` succeeded and the ledger recorded the confirmation

Pixel UI counts are local-ledger counts for the current registration history until the ledger is cleared or the device is unregistered. They are not a backend target/session aggregate by default. A backend dashboard should compare against `ImportedConfirmed` for the same target and time window if exact parity is required.
