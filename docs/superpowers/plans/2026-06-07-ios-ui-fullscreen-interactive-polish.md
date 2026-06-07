# iOS UI Full-Screen And Interactive Polish Plan

Date: 2026-06-07

## Goal

Polish the current iOS UI now that the core features work:

- Make setup and main app screens feel full-screen on iPhone, not like a centered web card.
- Reduce oversized icons and type on iPhone 12-sized screens.
- Make the photo mosaic interactive instead of display-only.
- Keep existing sync, queue, settings, and setup behavior working.

Android Pixel is out of scope.

## Observed Problems

From the simulator screenshots:

- Setup screen content sits inside a large white panel with unused black/device safe-area space around it.
- Main `Library Sync` screen also appears as a white content block rather than filling the app surface.
- Large title type is too heavy and consumes too much vertical space.
- Checklist icons are too large and create a crowded row layout.
- Tab bar icons are visually heavy.
- Photo mosaic only displays thumbnails; tapping does nothing.
- Content under the mosaic starts too low and can be clipped by the tab bar on small screens.
- Toolbar refresh icon is too large and floats far from the main visual rhythm.

## Current Files To Update

- `ios/iphone/NexusRelayIPhone/Core/Design/NRDesignSystem.swift`
- `ios/iphone/NexusRelayIPhone/Features/Setup/SetupView.swift`
- `ios/iphone/NexusRelayIPhone/Features/Setup/SetupChecklistView.swift`
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncView.swift`
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/PhotoMosaicView.swift`
- `ios/iphone/NexusRelayIPhone/Features/LibrarySync/LibrarySyncViewModel.swift`
- `ios/iphone/NexusRelayIPhone/Features/AppShell/AppShellView.swift`
- `ios/iphone/NexusRelayIPhone/Features/Queue/UploadQueueView.swift`
- `ios/iphone/NexusRelayIPhone/Features/Settings/SettingsView.swift`

## Design Direction

Use a native iOS utility-app style:

- Full-screen app background.
- Content aligned to safe areas, not centered in a large card.
- Compact typography and smaller symbols.
- Cards only for grouped controls and repeated items.
- Photo area behaves like a library preview: selectable thumbnails, larger preview, and entry points into queue/detail.
- Preserve current color tokens unless a spacing/token adjustment is needed.

## Phase 1: Fix Full-Screen Layout

### Setup Screen

Replace the current centered/card feel with a full-height layout:

- Use `ScrollView` with `contentMargins` or consistent horizontal padding.
- Ensure `nrPageBackground()` is applied to the full root, not just inner content.
- Add `frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)` to the root content where needed.
- Keep top padding safe-area aware, around `20-24`.
- Avoid wrapping the whole setup in one visual panel.

Target setup structure:

- Header
- Compact checklist
- Preferences group
- Error message
- Google login button fixed near bottom when possible

Use `safeAreaInset(edge: .bottom)` for the primary setup button if the content is short. This keeps the button reachable and prevents the screen from looking like a floating form.

### Library Sync Screen

Make the main tab content fill from top safe area to tab bar:

- Keep `NavigationStack`, but reduce title treatment.
- Use `.navigationBarTitleDisplayMode(.inline)` or a custom compact header inside content.
- Use root background that ignores safe area.
- Ensure the scroll view fills available height.
- Add bottom content padding so summary/actions do not hide behind tab bar.

Acceptance:

- No large white rectangle floating in the simulator.
- Background reaches top/bottom screen edges behind safe areas.
- Content uses full screen width with normal iOS margins.

## Phase 2: Resize Typography And Icons

### Design Tokens

Add compact icon and row metrics to `NRDesignSystem`:

- `IconSize.status = 20`
- `IconSize.row = 22`
- `IconSize.tab = default system size, no manual title-sized symbols`
- `Spacing.page = 16` on compact width
- `Spacing.section = 18` on compact width
- `Radius.row = 10`

Do not globally shrink everything blindly; update the specific oversized views.

### Setup Checklist

Current:

- status icon: `.title3`
- row icon: `.title3`
- row vertical padding: `14`
- divider leading: `86`

Target:

- status icon: `.system(size: 19, weight: .semibold)`
- row icon: `.system(size: 21, weight: .regular)`
- row vertical padding: `11-12`
- row title: `.subheadline.weight(.semibold)`
- row subtitle: `.caption`
- divider leading based on actual icon columns, around `72`

Also avoid long row titles wrapping awkwardly:

- Change `Destination Folder` to `Destination`.
- Use subtitle `iPhone Uploads`.

### Library Header

Current `Library Sync` large title is too big.

Target:

- Use `.title.weight(.bold)` or `.title2.weight(.bold)` on iPhone 12.
- Place refresh button as a compact circular/icon-only control aligned with header.
- Avoid large navigation title plus large in-content title at the same time.

### Tab Bar

Use standard `Label` tab items without forcing custom large icon fonts.

If the tab bar still looks oversized in screenshots:

- Audit whether simulator accessibility text size is enlarged.
- Ensure no `.font(.largeTitle)` or custom symbol rendering leaks into tab item labels.

## Phase 3: Make Photo Mosaic Interactive

### New Model

Replace `[UIImage]` with identifiable thumbnails:

```swift
struct LibraryPreviewItem: Identifiable, Equatable {
    let id: String
    let assetLocalIdentifier: String
    let image: UIImage
    let mediaType: LibraryPreviewMediaType
    let creationDate: Date?
}
```

`UIImage` is not `Equatable`, so if strict equality is awkward, keep the view model item non-Equatable and use `id` for rendering.

Add to `LibrarySyncViewModel`:

- `@Published var previewItems: [LibraryPreviewItem]`
- `@Published var selectedPreviewItem: LibraryPreviewItem?`
- Load recent images and videos if videos are enabled.
- Keep current thumbnail provider.

### PhotoMosaicView Interactions

Update `PhotoMosaicView` API:

```swift
struct PhotoMosaicView: View {
    let items: [LibraryPreviewItem]
    let selectedItemID: String?
    let onSelect: (LibraryPreviewItem) -> Void
}
```

Behavior:

- Each tile is a `Button`.
- Tapping a tile selects it.
- Selected tile shows a subtle accent border/check indicator.
- Video thumbnails show a small `play.fill` badge.
- Empty tiles remain non-interactive placeholders.

Layout:

- Use `LazyVGrid` or a custom responsive grid instead of fixed `Grid` if easier to scale.
- Height should adapt to device width, not hardcoded `260`.
- Suggested height: `min(280, max(210, availableWidth * 0.70))`.
- Keep 5-item mosaic pattern if it looks good, but make dimensions stable.

### Preview Detail

Add a lightweight detail surface for the selected image:

Option A, recommended:

- Tap tile opens a sheet with larger image preview and metadata/actions.

Sheet content:

- Large image
- Filename or asset date if available
- Upload status if we can map it from ledger/queue
- Buttons:
  - `View Queue`
  - `Sync Now`
  - `Close`

Option B:

- Tapping tile updates an inline selected preview below mosaic.

Recommendation:

Use sheet first. It is simpler, native, and avoids crowding the main screen.

### Queue Integration

Minimum viable interaction:

- Tile tap opens preview sheet.
- Sheet has `Sync Now`.

Better interaction:

- If the asset exists in upload ledger, show status and a `View in Queue` action.
- Pass a tab-routing callback from `AppShellView` so the sheet can switch to Queue tab.

Suggested app shell change:

- Introduce enum:

```swift
enum AppTab {
    case sync
    case queue
    case settings
}
```

- Add `@State private var selectedTab: AppTab = .sync`
- Bind `TabView(selection:)`.
- Let `LibrarySyncView` call `onOpenQueue()`.

## Phase 4: Main Sync Screen Composition

Target top-to-bottom layout:

1. Compact header row:
   - title: `Library Sync`
   - refresh icon button
2. Interactive mosaic
3. Status block:
   - percent or `Ready to Sync`
   - compact progress bar
   - summary counts
   - last sync
4. Primary action button:
   - `Sync`
   - `Pause`
5. Error or repair sign-in action

Important:

- The first visible area should not be only a giant title.
- Mosaic should sit high enough to be useful on iPhone 12.
- Primary action must not be hidden by the tab bar.

## Phase 5: Setup Screen Composition

Target layout:

1. Compact brand header:
   - `NexusRelay`
   - `Set up photo relay from this iPhone`
2. Checklist:
   - Account
   - Photos
   - Destination
3. Preferences:
   - Wi-Fi Only
   - Include Videos
   - Live Photo Video
4. Bottom Google button

Remove from setup:

- Server row
- Server field
- Any visual confirmation of backend URL

This overlaps with the Google login plan, but UI work should assume server is hidden.

## Phase 6: Queue And Settings Visual Consistency

Queue:

- Keep `List`, but reduce row thumbnail from `58` to `50-52` if rows feel heavy.
- Retry icon should use `.system(size: 22)` instead of `.title2`.
- Ensure detail sheet uses full background and native list grouping.

Settings:

- Remove backend URL row as part of fixed backend plan.
- Keep rows compact and native.
- Avoid large custom icon styling in settings rows unless needed.

## Phase 7: Accessibility And Dynamic Type

Check:

- Text should not clip at default simulator size.
- Titles should remain readable with larger accessibility text.
- Buttons need clear labels.
- Mosaic buttons need accessibility labels like `Recent photo, selected` or `Recent video`.
- Selected tile state should not rely only on color.

## Phase 8: Verification

Run app on:

- iPhone 12 simulator
- iPhone SE 3rd generation simulator if available
- One large device, for example iPhone 15 Pro Max

Screenshots to verify:

- Fresh setup screen
- Setup with error message
- Library Sync idle with thumbnails
- Library Sync after tapping a thumbnail
- Queue tab
- Settings tab

Visual acceptance:

- App fills the screen.
- No large centered white block.
- Icons fit the content rhythm.
- Header, mosaic, and primary action are visible without awkward clipping.
- Tapping photo mosaic produces visible behavior.
- Tab bar does not cover critical content.

Functional acceptance:

- Existing sync button still starts sync.
- Pause still works.
- Reconcile button still works.
- Queue tab still loads.
- Settings toggles still persist.
- Photo thumbnail loading still works with limited Photos access.

## Suggested Implementation Order

1. Add compact design tokens.
2. Fix setup screen root layout and checklist sizing.
3. Fix Library Sync root layout and header sizing.
4. Change `PhotoMosaicView` from static images to tappable preview items.
5. Add preview sheet for selected mosaic item.
6. Add optional tab selection routing from Sync to Queue.
7. Polish Queue retry icon and row sizing.
8. Remove server UI once the fixed backend login work lands.
9. Run simulator screenshots and adjust spacing once visually inspected.

## Risks

- The current repo has uncommitted UI changes, so implementation should read current files before editing and avoid overwriting unrelated work.
- `UIImage` cannot be used directly in `Equatable` models, so preview item identity should be based on `assetLocalIdentifier`.
- If Photos permission is limited, recent thumbnails may be sparse; placeholders should remain clean and non-broken.
- If tab selection routing is added, keep it small and avoid building a custom navigation system.

## Definition Of Done

- Setup and Library Sync screens are full-screen native layouts.
- Icon sizes are visibly smaller and consistent.
- Photo mosaic tiles are tappable.
- Tapping a mosaic item opens a useful preview or detail interaction.
- No backend URL is shown in iOS UI.
- Existing sync behavior remains intact.
- Simulator screenshots on iPhone 12 look acceptable before handoff.
