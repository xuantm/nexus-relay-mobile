# NexusRelay iPhone Photos Uploader

A native iOS application built with Swift and SwiftUI to upload photos and videos from Apple Photos directly into your NexusRelay storage.

## Features

- **SwiftUI Dashboard**: Clean, modern dark mode dashboard utilizing cards and glowing visual status alerts.
- **SQLite Ledger**: Persistent local queue database utilizing `libsqlite3` via C APIs to ensure state survives app restarts, crashes, or low memory events.
- **PhotoKit Integration**: Scans and discovers local photos/videos safely, including support for limited access permissions.
- **Fingerprinting & De-duplication**: Generates deterministic fingerprint suffixes (`__nr-<16-hex>`) to prevent duplicate uploads.
- **Robust Sync Engine**: Supports standard stream uploads for files up to 90 MB, and raw chunk uploads (30 MB chunks) for larger media files.
- **Network Awareness**: Optional Wi-Fi Only constraint to prevent uploading over cellular connections.
- **Background Support**: Schedules background processing tasks (`BGProcessingTask`) to complete uploads when the device is idle.

---

## Getting Started

### Prerequisites
- macOS 14.0 or newer
- Xcode 15.0 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (installable via Homebrew: `brew install xcodegen`)

### Generate and Build Project
To generate the Xcode project and build the simulator target:
```bash
# Generate project files
xcodegen generate

# Build target
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```

---

## Running Unit Tests

Unit tests cover the API client, Keychain storage, CSRF token handling, ledger transactions, export staging, and reconciliation services.

```bash
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test
```

---

## GitHub Actions

The repo includes two GitHub Actions workflows for the iPhone app:

- `iOS iPhone CI`: Runs on pull requests, selected branch pushes, and manual dispatch. It generates the Xcode project with XcodeGen, runs simulator tests, builds the simulator target, and uploads `.xcresult` bundles as artifacts.
- `iOS iPhone Release Artifact`: Runs manually or from tags matching `ios-iphone-v*`. It builds a Release simulator app bundle and an unsigned iOS device `.xcarchive`, then uploads both artifacts.

The release workflow intentionally avoids Apple code signing. That keeps the pipeline runnable without provisioning profiles or App Store Connect credentials, but it does not produce a TestFlight-ready IPA.

---

## Manual Verification
For instructions on verifying auth, CSRF tokens, cellular lockout, large file chunking, and folder reconciliation, see [manual-verification.md](docs/manual-verification.md).
