# NexusRelay Mobile

Mobile companion apps for NexusRelay.

## Repository Scope

This repo owns mobile clients only:

- `android/pixel`: Pixel companion app that receives media from NexusRelay.
- `ios/iphone`: future iPhone uploader app.
- `docs/contracts`: API contracts shared with the NexusRelay backend.
- `docs/architecture`: mobile architecture notes.
- `docs/implementation`: worker-oriented implementation plans.

The NexusRelay backend and web app remain in the main `nexus-relay` repo.

## Branches

- `main`: stable baseline and release-ready documentation/code.
- `develop`: integration branch for active mobile work.

Feature branches should branch from `develop`.

## Pixel App MVP

The first implementation target is the Pixel companion app:

```text
NexusRelay backend creates DeviceSyncJob
  -> FCM sends a small job-available signal
  -> Pixel app enqueues WorkManager sync
  -> Pixel app downloads media through NexusRelay API
  -> Pixel app imports media into Android MediaStore
  -> Pixel app confirms ImportedConfirmed
```

Read:

- [Pixel architecture](docs/architecture/pixel-companion-sync.md)
- [Device sync API contract](docs/contracts/device-sync-api.md)
- [Pixel implementation plan](docs/implementation/pixel-companion-app-plan.md)

