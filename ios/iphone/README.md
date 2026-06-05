# NexusRelay iPhone

iPhone Photos uploader for NexusRelay.

## Build

```bash
cd ios/iphone
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Test

```bash
cd ios/iphone
xcodegen generate
xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test
```
