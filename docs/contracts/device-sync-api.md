# Device Sync API Contract

This contract is consumed by the Pixel companion app and implemented by the NexusRelay backend.

## Auth

Device sync endpoints use a revocable device token:

```text
X-Device-Token: <device-token>
```

Claimed-job download requests must also send the active lease:

```text
X-Device-Sync-Lease: <lease-id>
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

### Claim Jobs

```http
POST /api/device-sync/jobs/claim
X-Device-Token: <device-token>
Content-Type: application/json
```

Request:

```json
{
  "workerRunId": "run-1",
  "limit": 25,
  "leaseSeconds": 900,
  "clientVersion": "pixel/1.0"
}
```

Response:

```json
{
  "leaseId": "8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef",
  "leaseExpiresAt": "2026-06-11T10:15:00Z",
  "remainingPendingCount": 7,
  "jobs": [
    {
      "jobId": "8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef",
      "mediaId": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1",
      "fileName": "IMG_1001.HEIC",
      "mimeType": "image/heic",
      "mediaType": "Image",
      "sizeBytes": 4820131,
      "sha256": "3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7",
      "downloadUrl": "/api/device-sync/jobs/8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef/download",
      "attemptNumber": 2,
      "createdAt": "2026-06-11T09:15:00Z"
    }
  ]
}
```

The Pixel app should keep claiming until `jobs` is empty or the worker run budget is reached.

### Download Claimed Job Media

```http
GET /api/device-sync/jobs/{jobId}/download
X-Device-Token: <device-token>
X-Device-Sync-Lease: <lease-id>
```

Expected response:

```text
200 OK or 206 Partial Content
Content-Type: image/heic | image/jpeg | video/mp4 | application/octet-stream
Content-Disposition: attachment; filename="<safe-file-name>"
```

The response streams bytes from the NexusRelay backend. The Pixel app must not call Google Drive directly.

### Heartbeat

```http
POST /api/device-sync/jobs/{jobId}/heartbeat
X-Device-Token: <device-token>
Content-Type: application/json
```

Request:

```json
{
  "leaseId": "8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef",
  "workerRunId": "run-1",
  "stage": "Downloading",
  "progressBytes": 2097152,
  "totalBytes": 4820131,
  "leaseSeconds": 900
}
```

Allowed `stage` values:

```text
Claimed
Downloading
Importing
Confirming
```

Response:

```json
{
  "leaseExpiresAt": "2026-06-11T10:20:00Z"
}
```

### Confirm Import

```http
POST /api/device-sync/jobs/{jobId}/confirm
X-Device-Token: <device-token>
Content-Type: application/json
```

Request:

```json
{
  "leaseId": "8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef",
  "workerRunId": "run-1",
  "importedUri": "content://media/external/images/media/12345",
  "importedSizeBytes": 4820131
}
```

### Report Failure

```http
POST /api/device-sync/jobs/{jobId}/fail
X-Device-Token: <device-token>
Content-Type: application/json
```

Request:

```json
{
  "leaseId": "8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef",
  "workerRunId": "run-1",
  "error": "Network disconnected during download",
  "retryable": true
}
```

The Pixel client must treat any terminal local failure as a backend-visible failure. If the client marks a job `Failed`, it must also call this endpoint rather than only updating local counters or ledger state.

### Wake Device

```http
POST /api/device-sync/me/targets/{targetId}/wake
Authorization: Bearer <web-session-access-token>
```

Response:

```json
{
  "signalSent": true
}
```

## FCM Payloads

FCM is a signal, not a file transport.

Job-available:

```json
{
  "type": "device_sync_job_available",
  "jobId": "8af63b26-f7af-4fe0-8cb5-5dc43edcc9ef"
}
```

Wake-requested:

```json
{
  "type": "device_sync_wake_requested",
  "targetId": "4d6b0f2e-47b6-49fd-8daa-c87e70307f9f"
}
```

The Pixel app should enqueue sync work after receiving either message, then reconcile from `POST /api/device-sync/jobs/claim`. FCM is not the durable queue.

## Status Vocabulary

Shared API status values:

```text
Pending
Syncing
Synced
Failed
```

Backend job states:

```text
Pending
Claimed
Downloading
Importing
Confirming
ImportedConfirmed
Failed
Cancelled
```

Projection:

- `Pending` -> `Pending`
- `Claimed`, `Downloading`, `Importing`, `Confirming` -> `Syncing`
- `ImportedConfirmed` -> `Synced`
- `Failed`, `Cancelled` -> `Failed`

## Lease Expiry

Android background execution is not infinite. The protocol relies on leases and heartbeats instead.

- Claimed jobs expire when `LeaseExpiresAt` passes without a heartbeat.
- Expired active attempts are marked failed by the backend sweep.
- If retry budget remains and no active duplicate exists, the backend creates a fresh pending retry attempt.
- Pixel should wake again through FCM, polling fallback, or manual wake from the web dashboard.
