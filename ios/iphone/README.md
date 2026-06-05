# NexusRelay iPhone Photos Uploader

A native iOS application built with Swift and SwiftUI to upload photos and videos from Apple Photos directly into your NexusRelay storage.

## Features

- **SwiftUI Dashboard**: Clean, modern dark mode dashboard utilizing cards and glowing visual status alerts.
- **SQLite Ledger**: Persistent local queue database utilizing `libsqlite3` via C APIs to ensure state survives app restarts, crashes, or low memory events.
- **PhotoKit Integration**: Scans and discovers local photos/videos safely, including support for limited access permissions.
- **Fingerprinting & De-duplication**: Generates deterministic fingerprint suffixes (`__nr-<16-hex>`) to prevent duplicate uploads.
- **Robust Sync Engine**: Supports standard stream uploads for files $\le$ 90 MB, and chunked multipart uploads (30 MB chunks) for larger media files.
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

## Manual Verification
For instructions on verifying auth, CSRF tokens, cellular lockout, large file chunking, and folder reconciliation, see the [Manual Verification Guide](file:///g:/workspace/nexus-relay-mobile/ios/iphone/docs/manual-verification.md).
