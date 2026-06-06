import SwiftUI

struct LibrarySyncView: View {
    @StateObject private var viewModel: LibrarySyncViewModel

    init(syncStatusViewModel: SyncStatusViewModel = SyncStatusViewModel()) {
        _viewModel = StateObject(wrappedValue: LibrarySyncViewModel(syncStatusViewModel: syncStatusViewModel))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NRDesign.Spacing.section) {
                    if viewModel.summary.total == 0 {
                        ContentUnavailableView(
                            "No items ready to upload",
                            systemImage: "photo.on.rectangle",
                            description: Text("Tap Sync after granting Photos access.")
                        )
                        .padding(.vertical, 40)
                    } else {
                        PhotoMosaicView(images: viewModel.mosaicImages)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(viewModel.summary.progressPercentText)
                                .font(.largeTitle.bold())
                                .foregroundStyle(NRDesign.ColorToken.primaryText)

                            ProgressView(value: viewModel.summary.progressFraction)
                                .tint(NRDesign.ColorToken.accent)

                            Text(viewModel.summary.summaryText)
                                .font(.callout)
                                .foregroundStyle(NRDesign.ColorToken.primaryText)

                            if let lastSync = viewModel.lastSyncDate {
                                Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
                            }
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(NRDesign.ColorToken.error)
                    }

                    Button {
                        Task { await viewModel.syncNow() }
                    } label: {
                        Label(viewModel.activeStatus == .idle ? "Sync" : "Syncing", systemImage: "icloud.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(NRDesign.ColorToken.accent)
                    .disabled(viewModel.activeStatus != .idle)
                    .accessibilityLabel("Start NexusRelay sync")
                    .accessibilityHint("Scans Photos and uploads pending items to the selected NexusRelay folder")
                }
                .padding(NRDesign.Spacing.page)
            }
            .navigationTitle("Library Sync")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.reconcile() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityLabel("Rebuild upload history")
                }
            }
            .nrPageBackground()
            .task {
                viewModel.refreshFromSyncViewModel()
                await viewModel.loadMosaicImages()
            }
        }
    }
}
