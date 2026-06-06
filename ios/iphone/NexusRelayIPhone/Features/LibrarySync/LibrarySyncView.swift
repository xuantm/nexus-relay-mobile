import SwiftUI

struct LibrarySyncView: View {
    @StateObject private var viewModel = LibrarySyncViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NRDesign.Spacing.section) {
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
