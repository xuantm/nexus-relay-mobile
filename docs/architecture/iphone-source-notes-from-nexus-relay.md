# iPhone Source Notes From NexusRelay Repo

This file captures iPhone-related source notes that previously existed outside the mobile repository, so future iPhone work can stay anchored in `nexus-relay-mobile`.

## Source: `nexus-relay/ultimate_system_audit_report.md`

The backend repository contained one iPhone-related implementation note in the system audit report. It described an existing browser upload UX pattern that helps iOS Safari avoid freezing while selected files are being prepared.

Relevant note:

```text
The upload page already implements the most important iOS handshake pattern from the prompt:
```

```tsx
setIsPreparing(true);
window.setTimeout(() => {
  const nextFiles = Array.from(selectedFiles);
  setFiles((prev) => [...prev, ...nextFiles]);
  input.value = '';
  setIsPreparing(false);
}, 0);
```

Why this matters:

- It yields to the browser before heavy file analysis.
- It shows a "Preparing assets..." state immediately.
- It reduces the chance of Safari appearing frozen after large file selection.

Why this is only a source note:

- The iPhone uploader app planned in this repository is native iOS, not a Safari web flow.
- The exact code above should not be copied into the Swift app.
- The product lesson should carry over: yield early, show a visible preparing state, and avoid blocking the main thread during large asset preparation.

## Repository Boundary

The actual iPhone app architecture, contract, implementation plan, and Hermes prompt now live in this repository:

- `docs/architecture/iphone-photos-uploader.md`
- `docs/contracts/iphone-upload-api.md`
- `docs/implementation/iphone-photos-uploader-plan.md`
- `docs/implementation/iphone-photos-uploader-hermes-prompt.md`

The `nexus-relay` repository should keep backend-facing API and device-sync docs only.
