# iPhone Photos Uploader Hermes Prompt

Use this prompt to coordinate Agy/Hermes for implementing the iPhone Photos uploader in this repository.

```text
Implement the iPhone Photos uploader in repo /workspace/nexus-relay-mobile.

Branch:
- Start from develop.
- Create feature/ios-photos-uploader.
- Do not work on main/develop directly.

Required docs to read first:
- README.md
- docs/architecture/iphone-photos-uploader.md
- docs/contracts/iphone-upload-api.md
- docs/implementation/iphone-photos-uploader-plan.md

Scope:
- Implement only iOS app under ios/iphone.
- Follow the implementation plan task-by-task.
- iPhone app uploads Photos media to NexusRelay.
- Do not implement Pixel receiver changes.
- Do not implement backend changes.
- Do not call Google Drive directly.
- Use existing NexusRelay backend upload/auth/folder APIs from the contract docs.

Execution:
- Use Superpowers subagent-driven-development.
- Assign one fresh dev worker per plan part when possible.
- After each part, run relevant tests/build.
- Then run Codex review:
  1. spec compliance review
  2. code quality review
- If review is not clean, send findings back to Agy to fix.
- Repeat fix -> review until no blocker/major findings remain.
- Continue until all parts pass.

Verification:
- On macOS worker/CI, run:
  cd ios/iphone
  xcodegen generate
  xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' test
  xcodebuild -scheme NexusRelayIPhone -destination 'platform=iOS Simulator,name=iPhone 16' build
- If real iPhone is unavailable, report manual verification as NOT RUN with reason.

Expected final report:
- Branch name
- Commit list
- Parts completed
- Tests/build commands and results
- Review rounds and final review status
- Known limitations
- Files changed
```
