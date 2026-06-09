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

## FCM Payload

FCM is a signal, not a file transport.

```json
{
  "type": "device_sync_job_available",
  "jobId": "8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef"
}
```

The Pixel app should enqueue sync work after receiving this message, then call `GET /api/device-sync/jobs/pending`. The app should not trust FCM as the durable queue.

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
