# AGENTS.md - iOS iPhone

Root rules still apply: see `../../AGENTS.md`.

## Commands
```bash
xcodegen generate --spec project.yml
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -project NexusRelayIPhone.xcodeproj -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Local Rules
- Edit `project.yml` before regenerating the Xcode project.
- Do not commit provisioning profiles, signing credentials, Keychain data, cookies, or local `ledger.sqlite`.
- Auth, CSRF, upload, ledger, PhotoKit, and background changes should have focused XCTest coverage.

## Context
Relevant context starts at `../../.codex/context/index.md`, especially `mobile/ios-iphone.md`, `contracts/api-contracts.md`, `database/local-persistence.md`, `security/auth-and-data-protection.md`, and `mobile/build-signing.md`.
