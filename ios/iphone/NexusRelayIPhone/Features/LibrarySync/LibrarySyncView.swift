import SwiftUI

@MainActor
struct LibrarySyncView: View {
    @StateObject private var viewModel: LibrarySyncViewModel
    private let onRepairSignIn: () -> Void
    private let onOpenQueue: () -> Void

    init(
        syncStatusViewModel: SyncStatusViewModel? = nil,
        onRepairSignIn: @escaping () -> Void = {},
        onOpenQueue: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: LibrarySyncViewModel(syncStatusViewModel: syncStatusViewModel ?? SyncStatusViewModel()))
        self.onRepairSignIn = onRepairSignIn
        self.onOpenQueue = onOpenQueue
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NRDesign.ColorToken.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if viewModel.summary.total == 0 && viewModel.previewItems.isEmpty {
                            emptyStateBlock
                        } else {
                            PhotoMosaicView(
                                items: viewModel.previewItems,
                                selectedItemID: viewModel.selectedPreviewItem?.id,
                                onSelect: { item in
                                    viewModel.selectedPreviewItem = item
                                }
                            )
                            statusBlock
                        }
                        actionBlock
                        supportBlock
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, NRDesign.Spacing.page)
                    .padding(.top, 18)
                    .padding(.bottom, 72)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                viewModel.refreshFromSyncViewModel()
                await viewModel.loadPreviewItems()
            }
            .sheet(item: $viewModel.selectedPreviewItem) { item in
                LibraryPreviewDetailView(
                    item: item,
                    progressText: viewModel.summary.progressPercentText,
                    onOpenQueue: onOpenQueue,
                    onSyncNow: {
                        Task { await viewModel.syncNow() }
                    }
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Library Sync")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(NRDesign.ColorToken.primaryText)

                Text(viewModel.activeStatus == .idle ? "Ready to scan this iPhone library" : "Keeping this library in sync")
                    .font(.footnote)
                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button {
                Task { await viewModel.reconcile() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NRDesign.ColorToken.accent)
                    .frame(width: 32, height: 32)
                    .background(NRDesign.ColorToken.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rebuild upload history")
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.summary.total == 0 {
                Text("Ready to Sync")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NRDesign.ColorToken.primaryText)

                Text("Tap Sync to scan Photos and upload pending items.")
                    .font(.footnote)
                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
            } else {
                Text(viewModel.summary.progressPercentText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NRDesign.ColorToken.primaryText)

                ProgressView(value: viewModel.summary.progressFraction)
                    .tint(NRDesign.ColorToken.accent)

                Text(viewModel.summary.summaryText)
                    .font(.footnote)
                    .foregroundStyle(NRDesign.ColorToken.primaryText)

                if let lastSync = viewModel.lastSyncDate {
                    Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(NRDesign.ColorToken.secondaryText)
                }
            }

            HStack(spacing: 8) {
                statChip(title: "Uploaded", value: "\(viewModel.summary.uploaded)")
                statChip(title: "Waiting", value: "\(viewModel.summary.waiting)")
                statChip(title: "Failed", value: "\(viewModel.summary.failed)")
                statChip(title: "Active", value: "\(viewModel.summary.active)")
            }
        }
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NRDesign.ColorToken.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(NRDesign.ColorToken.surface, in: RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous)
                .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
        )
    }

    private var actionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if viewModel.activeStatus == .scanning || viewModel.activeStatus == .exporting || viewModel.activeStatus == .uploading {
                    viewModel.pauseSync()
                } else if viewModel.activeStatus == .idle || viewModel.activeStatus == .error {
                    Task { await viewModel.syncNow() }
                }
            } label: {
                Label(primaryActionTitle, systemImage: "icloud.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(NRDesign.ColorToken.accent)
            .disabled(viewModel.activeStatus == .pausing)
            .accessibilityLabel(viewModel.activeStatus == .idle || viewModel.activeStatus == .error ? "Start NexusRelay sync" : "Pause NexusRelay sync")
            .accessibilityHint(viewModel.activeStatus == .idle || viewModel.activeStatus == .error ? "Scans Photos and uploads pending items to the selected NexusRelay folder" : "Stops the queue after the current item finishes")

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(NRDesign.ColorToken.error)
            }
        }
    }

    private var emptyStateBlock: some View {
        ContentUnavailableView(
            "No items ready to upload",
            systemImage: "photo.on.rectangle",
            description: Text("Grant Photos access, then tap Sync to scan your library.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var supportBlock: some View {
        Group {
            if viewModel.requiresSignInRepair {
                Button("Repair Sign-In") {
                    onRepairSignIn()
                }
                .buttonStyle(.bordered)
                .tint(NRDesign.ColorToken.accent)
            }
        }
    }

    private var primaryActionTitle: String {
        switch viewModel.activeStatus {
        case .idle, .error:
            return "Sync"
        case .pausing:
            return "Pausing"
        case .scanning, .exporting, .uploading:
            return "Pause"
        }
    }
}

private struct LibraryPreviewDetailView: View {
    let item: LibraryPreviewItem
    let progressText: String
    let onOpenQueue: () -> Void
    let onSyncNow: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(NRDesign.ColorToken.primaryText)

                        Text(detailSubtitle)
                            .font(.callout)
                            .foregroundStyle(NRDesign.ColorToken.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Type", value: item.mediaType.accessibilityLabel)
                        LabeledContent("Progress", value: progressText)
                        if let creationDate = item.creationDate {
                            LabeledContent("Captured", value: creationDate.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(NRDesign.ColorToken.surface, in: RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: NRDesign.Radius.row, style: .continuous)
                            .stroke(NRDesign.ColorToken.hairline, lineWidth: 1)
                    )

                    VStack(spacing: 10) {
                        Button("View Queue") {
                            dismiss()
                            onOpenQueue()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("Sync Now") {
                            dismiss()
                            onSyncNow()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)

                        Button("Close", role: .cancel) {
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(NRDesign.Spacing.page)
            }
            .background(NRDesign.ColorToken.appBackground.ignoresSafeArea())
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var detailSubtitle: String {
        var pieces: [String] = [item.mediaType.accessibilityLabel]
        if let creationDate = item.creationDate {
            pieces.append(creationDate.formatted(date: .abbreviated, time: .shortened))
        }
        return pieces.joined(separator: " · ")
    }

    private var displayName: String {
        guard let filename = item.filename, !filename.isEmpty else {
            return item.mediaType.accessibilityLabel
        }

        return filename
    }
}
