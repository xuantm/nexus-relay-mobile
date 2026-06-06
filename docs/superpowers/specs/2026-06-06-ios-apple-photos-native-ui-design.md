# iOS Apple Photos Native UI Design

## Status

Approved visual direction: Option A, Apple Photos Native.

Mockup reference:

- `docs/superpowers/assets/iphone-apple-photos-native-option-a.png`

## Product Context

The iPhone app is a native Photos uploader for NexusRelay. It scans Photos with PhotoKit, keeps a local upload ledger, exports originals into app-private temporary storage, uploads through NexusRelay APIs, and uses background work only as a best-effort recovery path. It is not a Pixel receiver and it never talks to Google Drive directly.

The UI should make the app feel like a quiet iOS utility that belongs next to Apple Photos: familiar, low-friction, fast to understand, and calm when uploads need attention.

## Design Principles

- Native first: use SwiftUI patterns that feel close to Apple Photos and Settings.
- Minimal chrome: avoid heavy dashboards, decorative panels, and technical jargon on primary screens.
- Photos lead the experience: thumbnails, library counts, and recent activity should carry more visual weight than abstract charts.
- Manual sync is reliable and obvious: foreground "Sync" remains the clearest primary action.
- Problems are recoverable: failed or paused items should show clear next actions without making the whole app feel broken.
- Privacy is visible but not wordy: the app should state that passwords are not stored and photos remain local until upload starts.

## Information Architecture

Use a simple three-tab structure after setup:

```text
Library Sync
Queue
Settings
```

Setup appears only when required. If setup is incomplete, app launch opens the checklist. If setup is complete, app launch opens Library Sync.

Primary navigation:

- `Library Sync`: status, progress, recent uploads, and primary sync action.
- `Queue`: active, waiting, and failed upload rows.
- `Settings`: server/account, destination folder, Photos access, and sync preferences.

## Screen 1: Setup Checklist

Purpose: get the user connected without making them understand backend details.

Layout:

- Title: `NexusRelay`
- Subtitle: short status line such as `Set up photo relay from this iPhone`
- Four checklist rows:
  - `Server`
  - `Sign in`
  - `Photos Access`
  - `Destination Folder`
- Each row uses an iOS list style with icon, label, compact status, and chevron.
- Bottom action: `Continue`

Behavior:

- Completed rows show a checkmark.
- Required incomplete rows show a neutral pending state.
- Error rows show a short message and remain tappable.
- Destination defaults to `iPhone Uploads`; if missing, the app offers to create it.
- Photos access supports full and limited access. Limited access is valid but should be labeled.

Copy rules:

- Use `Photos Access`, not `PhotoKit permission`.
- Use `Destination Folder`, not `backend folder id`.
- Use `Sign in again` when auth refresh fails.

## Screen 2: Library Sync Home

Purpose: answer "is my library uploading correctly?" within one glance.

Layout:

- Large title: `Library Sync`
- Photo mosaic header with recent local or recently uploaded thumbnails.
- Slim progress bar below the mosaic.
- Compact progress text: `68% uploaded`
- Summary line: `842 uploaded · 319 waiting · 3 need attention`
- Primary bottom toolbar action: `Sync`
- Secondary toolbar destinations: `Queue`, `Settings`

Behavior:

- If idle and ready, primary action is `Sync`.
- If uploading, primary action becomes `Pause`.
- If Wi-Fi only blocks upload on cellular, show `Waiting for Wi-Fi` near the progress line.
- If auth is invalid, show `Sign in required` and route to setup/sign-in repair.
- If Photos access is limited, show a small status row that opens the system limited-library picker.

Visual emphasis:

- Thumbnails are the hero, not a chart.
- Progress is present but understated.
- Failed count is visible, but does not dominate unless failures block useful work.

## Screen 3: Queue And Attention

Purpose: give the user confidence that stuck uploads can be inspected and fixed.

Layout:

- Title: `Needs Attention` when filtered to failed items, otherwise `Upload Queue`.
- Segmented control:
  - `All`
  - `Active`
  - `Failed`
- Native list rows with:
  - thumbnail
  - filename
  - status label
  - progress bar for active uploads
  - retry action for failed uploads
- Bottom action for failed filter: `Retry all`

Statuses:

- `Preparing`
- `Uploading`
- `Waiting for Wi-Fi`
- `Needs iCloud download`
- `Sign in required`
- `Failed`
- `Uploaded`

Behavior:

- Tapping a row opens a detail sheet with file size, upload mode, last error, destination folder, and retry action.
- Failed retry should keep the same backend-visible fingerprinted filename.
- Rows should not expose raw Photos local identifiers.

## Settings

Settings should feel like a compact iOS Settings page, not a control panel.

Rows:

- Account: current NexusRelay username and sign-out action.
- Server: backend base URL.
- Destination Folder: selected folder name.
- Photos Access: full, limited, denied, or restricted.
- Wi-Fi Only: toggle, default on.
- Include Videos: toggle, default on.
- Live Photo Video: toggle, default off.
- Background Sync: status row, not a promise of full automatic backup.

Danger actions:

- `Clear local upload history` should be behind a confirmation sheet.
- Sign out should not delete already uploaded backend media.

## Visual System

Palette:

- Background: `#FAFAF8`
- Surface: `#FFFFFF`
- Primary text: `#171717`
- Secondary text: `#6B7280`
- Hairline border: `#E6E7E3`
- Accent: `#0A84A5`
- Success: `#2EAD6B`
- Warning: `#F2B84B`
- Error: `#D84A4A`

Typography:

- Use native iOS dynamic type and SF Pro defaults.
- Prefer `largeTitle` for screen titles, `headline` for important rows, and `caption` for status text.
- Do not use negative letter spacing.

Components:

- Native `List` and `NavigationStack` patterns where possible.
- Rounded thumbnails with 6-8 pt radius.
- Large bottom actions use iOS capsule style.
- Avoid nested cards. Use lists, sections, dividers, and lightweight surfaces.
- Use SF Symbols for setup, sync, queue, folder, warning, retry, and settings icons.

Motion:

- Progress changes should animate gently.
- Row status transitions should be subtle.
- Setup checklist completion can use a small checkmark transition.
- Avoid decorative motion that competes with upload status.

## Empty, Loading, And Error States

First launch:

- Show setup checklist immediately.

Scanning:

- Show `Preparing library...` quickly before heavy PhotoKit work starts.
- Keep the UI responsive while scanning.

Empty library or no matching assets:

- Show `No items ready to upload` with a Photos access action if access is limited.

No network:

- Show `Waiting for connection` and keep queued work visible.

Backend unavailable:

- Show `Server unavailable` with retry and settings link.

Auth expired:

- Pause queue and show `Sign in required`.

Ledger recovery:

- Show a quiet banner: `Rebuilding upload history`.
- Do not expose database language to the user.

## Accessibility

- All controls must support Dynamic Type without clipping.
- Buttons must meet 44 pt minimum hit target.
- Progress cannot rely on color alone; include labels.
- Queue rows need VoiceOver labels that summarize filename, status, and action.
- Color contrast should pass WCAG AA for normal text.
- Limited Photos access and Wi-Fi-only blocked states must be understandable without reading tiny captions.

## Implementation Notes For Future Plan

- SwiftUI should use `NavigationStack`, `List`, `Section`, `Toolbar`, `ProgressView`, `PhotosPicker` or PhotoKit authorization flows, and SF Symbols.
- Keep UI state separate from upload orchestration. View models should consume ledger counts, current sync status, and queue records through small protocols.
- Prefer a small design token layer for colors, spacing, and status styles so Setup, Sync Home, Queue, and Settings stay consistent.
- Do not implement a complex analytics dashboard for MVP. Option A is intentionally closer to Apple Photos than to an operations console.

## Acceptance Criteria

- A user can complete setup without learning CSRF, cookies, chunking, or ledger concepts.
- The home screen clearly communicates whether upload is ready, active, blocked, or needs attention.
- The queue makes retryable failures discoverable and fixable.
- Settings expose the required MVP controls without overwhelming the sync home.
- The UI remains readable on smaller iPhones and with larger Dynamic Type.
- The design stays light, native, and photo-forward, matching Option A.

## Out Of Scope

- TestFlight or App Store release UI.
- Pixel receiver controls.
- Google Drive controls.
- Full automatic backup guarantees.
- Advanced upload throughput charts.
- Dark-only design direction.
