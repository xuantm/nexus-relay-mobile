import SwiftUI

@MainActor
struct LibrarySyncView: View {
    @StateObject private var viewModel: LibrarySyncViewModel
    private let onRepairSignIn: () -> Void

    init(
        syncStatusViewModel: SyncStatusViewModel? = nil,
        onRepairSignIn: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: LibrarySyncViewModel(syncStatusViewModel: syncStatusViewModel ?? SyncStatusViewModel()))
        self.onRepairSignIn = onRepairSignIn
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NRDesign.Spacing.section) {
                    if viewModel.summary.total == 0 && viewModel.mosaicImages.isEmpty {
                        ContentUnavailableView(
                            "No items ready to upload",
                            systemImage: "photo.on.rectangle",
                            description: Text("Tap Sync after granting Photos access.")
                        )
                        .padding(.vertical, 40)
                    } else {
                        PhotoMosaicView(images: viewModel.mosaicImages)

                        VStack(alignment: .leading, spacing: 10) {
                            if viewModel.summary.total == 0 {
                                Text("Ready to Sync")
                                    .font(.largeTitle.bold())
                                    .foregroundStyle(NRDesign.ColorToken.primaryText)

                                Text("Tap Sync below to scan your library and start uploading.")
                                    .font(.callout)
                                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
                            } else {
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
                    }

                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(NRDesign.ColorToken.error)
                    }

                    if viewModel.requiresSignInRepair {
                        Button("Repair Sign-In") {
                            onRepairSignIn()
                        }
                        .buttonStyle(.bordered)
                    }

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
