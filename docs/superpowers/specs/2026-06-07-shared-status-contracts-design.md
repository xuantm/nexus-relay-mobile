# Shared Status Contracts Design

**Goal:** Preserve the backend, Pixel, and iPhone internal recovery states while exposing simple shared status enums for user-facing sync and upload progress.

**Decision:** Use internal states for resumability and diagnostics, and project them into simplified shared statuses at API and UI boundaries.

## Status Contracts

Pixel receive flow exposes:

```csharp
public enum SyncStatus
{
    Pending,
    Syncing,
    Synced,
    Failed
}
```

iPhone upload-to-Drive flow exposes:

```csharp
public enum UploadStatus
{
    Pending,
    Uploading,
    Uploaded,
    Failed
}
```

## Backend Mapping

`DeviceSyncJobStatus` remains the backend persistence enum for Pixel jobs. The user-facing projection maps:

- `Pending`, `Notified` -> `Pending`
- `Downloading` -> `Syncing`
- `ImportedConfirmed` -> `Synced`
- `Failed`, `Skipped`, `Cancelled` -> `Failed`

`MediaItemStatus` remains the backend persistence enum for upload relay. The user-facing projection maps:

- `Pending` -> `Pending`
- `Buffering`, `Relaying` -> `Uploading`
- `Completed` -> `Uploaded`
- `Failed` -> `Failed`

## Mobile Mapping

Pixel keeps `LocalSyncStatus` for resume checkpoints:

- `Queued` -> `Pending`
- `Downloading`, `Imported`, `ConfirmPending` -> `Syncing`
- `Confirmed` -> `Synced`
- `Failed` -> `Failed`

iPhone renames the current persistent ledger enum to `UploadLedgerStatus` and adds the shared `UploadStatus` projection:

- `discovered`, `readyToUpload`, `skipped` -> `Pending`
- `exporting`, `uploading` -> `Uploading`
- `uploaded`, `synced` -> `Uploaded`
- `failed` -> `Failed`

The existing SQLite and DataStore raw values remain compatible; no mobile data wipe is required.

## API Contract

Backend DTOs should include the simplified status fields without removing existing internal storage or endpoint sequencing:

- Device sync job DTOs expose `status: "Pending" | "Syncing" | "Synced" | "Failed"`.
- Media item DTOs expose `uploadStatus: "Pending" | "Uploading" | "Uploaded" | "Failed"` while preserving existing `status` for web compatibility.

Endpoint names such as `/api/device-sync/jobs/{jobId}/downloading` can remain for backward compatibility. The endpoint marks the backend internal job as `Downloading`, which projects to user-facing `Syncing`.

## Testing

Add focused tests for the projection functions, mobile DTO decoding, ledger mapping, and UI labels. Existing sync/upload transition tests should remain intact because they protect the internal recovery states.

