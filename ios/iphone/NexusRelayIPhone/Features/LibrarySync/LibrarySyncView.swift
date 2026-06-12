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
                        if viewModel.dashboard.uploadedText == "0" &&
                            viewModel.dashboard.waitingText == "0" &&
                            viewModel.dashboard.activeText == "0" &&
                            viewModel.dashboard.failedText == "0" &&
                            viewModel.activeStatus == .idle {
                            emptyStateBlock
                        } else {
                            SyncProgressHeroCard(dashboard: viewModel.dashboard)
                            SyncStageCards(dashboard: viewModel.dashboard)
                            SyncMetricGrid(dashboard: viewModel.dashboard)
                            SyncQueueHealthCard(dashboard: viewModel.dashboard)
                        }
                        SyncDashboardActionBar(
                            dashboard: viewModel.dashboard,
                            onPrimaryAction: {
                                if viewModel.dashboard.canPause {
                                    viewModel.pauseSync()
                                } else {
                                    Task { await viewModel.syncNow() }
                                }
                            },
                            onOpenQueue: onOpenQueue
                        )
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
}
