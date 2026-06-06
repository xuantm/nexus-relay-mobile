Implement the native iPhone Photos uploader in `G:/workspace/nexus-relay-mobile`.

Execution mode:

- Use the current repository as the writable workspace.
- You may read `G:/workspace/nexus-relay` for backend/frontend contract reference, but do not modify files there.
- Continue until the iPhone uploader plan is fully implemented or you are genuinely blocked.
- Do not stop for progress check-ins.

Primary source of truth:

- `G:/workspace/nexus-relay-mobile/docs/superpowers/plans/2026-06-05-ios-photos-uploader-current-docs.md`

Read before making changes:

- `G:/workspace/nexus-relay-mobile/README.md`
- `G:/workspace/nexus-relay-mobile/docs/architecture/iphone-photos-uploader.md`
- `G:/workspace/nexus-relay-mobile/docs/contracts/iphone-upload-api.md`
- `G:/workspace/nexus-relay-mobile/docs/implementation/iphone-photos-uploader-plan.md`
- `G:/workspace/nexus-relay-mobile/docs/architecture/iphone-source-notes-from-nexus-relay.md`
- `G:/workspace/nexus-relay/docs/upload_flow_under_90mb.md`
- `G:/workspace/nexus-relay/docs/upload_flow_above_90mb.md`
- `G:/workspace/nexus-relay/docs/system_architecture.md`
- `G:/workspace/nexus-relay/frontend/lib/workers/upload.worker.ts`
- `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Api/Endpoints/UploadEndpoints.cs`
- `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Api/Endpoints/AuthEndpoints.cs`
- `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Api/Program.Helpers.cs`
- `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Application/DTOs/Contracts.cs`

Non-negotiable scope:

- Build only the iPhone uploader under `ios/iphone`.
- iOS is an uploader only. It is not a device-sync receiver.
- Do not modify Android/Pixel work.
- Do not modify the backend repo.
- Do not call Google Drive directly from iOS code.
- Do not store the user password after login.
- Do not expose raw Photos `localIdentifier` values in uploaded file names.

Contract rules you must honor:

- Cookie auth is the MVP auth mode.
- Unsafe requests currently require CSRF.
- Implement `GET /api/auth/csrf` consumption and send `X-NexusRelay-CSRF` on unsafe requests.
- Keep backend cookies, including `access_token`, `refresh_token`, and `nexus_csrf`.
- Support one-shot `401 -> refresh -> retry original request once`.
- `GET /api/folders/{id}/media` must decode the current `FolderContentDto` shape.
- Stream upload threshold: `<= 90 MB`.
- Chunked upload threshold: `> 90 MB`.
- Chunk size: `30 MB`.
- `/api/upload/chunk` uses raw `application/octet-stream` request bodies with `x-upload-id`, `x-chunk-index`, and `x-chunk-size`.
- URL-encode `x-file-name` before sending it.
- Use file-backed upload tasks, not in-memory full-file buffers.

Execution plan:

- Implement all milestones from Milestone 0 through Milestone 11 in `2026-06-05-ios-photos-uploader-current-docs.md`.
- Work milestone by milestone in dependency order.
- Run relevant tests/build validation after each milestone where feasible.
- Update docs first when the plan requires contract alignment before code.

Quality bar:

- Follow TDD where practical.
- Keep files focused and small.
- Add tests for networking/auth/CSRF, fingerprinting, ledger transitions, reconciliation, and upload engine behavior.
- Prefer deterministic unit tests using fakes/protocol abstractions.
- Make manual verification docs explicit about what was and was not run.

Repository hygiene:

- Leave unrelated untracked files alone, especially:
  - `G:/workspace/nexus-relay-mobile/fix_endpoints.py`
  - `G:/workspace/nexus-relay-mobile/window_dump.xml`
- Do not revert user changes.
- Use non-interactive git commands.
- Commit logically by milestone when a milestone is complete and verified.

Expected deliverables:

- Updated mobile contract docs reflecting CSRF and folder media response reality.
- A buildable iOS app scaffold under `ios/iphone`.
- Swift/SwiftUI implementation for auth, settings, PhotoKit scan, SQLite ledger, export staging, upload engine, reconciliation, orchestration, background retry, and setup/status UI.
- Tests and CI workflow.
- Manual verification doc.

Final response format:

- Summarize milestones completed.
- List verification commands run and the outcome of each.
- List commits created.
- List any blockers or items not run.
