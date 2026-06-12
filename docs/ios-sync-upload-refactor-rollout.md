# iOS Sync Upload Refactor Rollout

## Metrics to Compare

- Files uploaded per minute.
- Megabytes uploaded per minute.
- Files per minute by upload route: direct multipart, direct resumable, and chunked.
- Average export duration.
- Average upload duration.
- Average upload duration by route.
- Retry count and final failed count.
- Peak memory while chunking large videos.
- UI progress update cadence during foreground sync.

## Device Test: 50 Files

1. Sign in with Google through the existing setup flow.
2. Select the destination folder.
3. Enable Wi-Fi only.
4. Start Sync with 50 mixed images and videos.
5. Confirm the Sync page shows counts, active state, and smooth progress.
6. Confirm Queue updates without visible reload flicker.
7. Confirm uploads appear on the web dashboard.
8. Confirm Pixel confirms synced items after download.

Expected result: no duplicate uploads, no stuck active item, and progress moves while upload is active.

## Device Test: 500 Files

1. Start from a clean or known ledger.
2. Sync 500 images on the same network used for baseline testing.
3. Record total elapsed time.
4. Record files per minute and MB per minute from unified logs.
5. Background the app for 5 minutes, then foreground it.
6. Confirm ledger counts remain consistent.

Expected result: foreground throughput improves versus the sequential baseline, and background/foreground transitions do not corrupt queue state.

## Useful Log Filters

Use Console.app or device logs and filter:

```text
subsystem:com.nexusrelay.iphone category:sync
subsystem:com.nexusrelay.iphone category:upload
```

Key events:

- `sync.scan.completed`
- `sync.batch.started`
- `sync.record.completed`
- `sync.record.failed`
- `upload.record.started`
- `upload.chunked.started`
- `upload.chunk.completed`
- `upload.chunked.completed`

## Rollback

If record concurrency causes backend pressure, set `UploadPolicy.nexusRelayDefault.recordUploadConcurrency` to `1` and rebuild.

If progress UI feels noisy, increase `UploadPolicy.nexusRelayDefault.progressThrottleMilliseconds` from `300` to `500`.

If chunking large videos raises memory pressure, lower `UploadPolicy.nexusRelayDefault.chunkCopyBufferSize`.

## Known Limits

iOS background execution remains best-effort. Foreground sync should be treated as the reliable path for large first-time syncs.
