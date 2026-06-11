import SwiftUI

@MainActor
struct PixelDeliveryView: View {
    @StateObject private var viewModel: PixelDeliveryViewModel

    init(viewModel: PixelDeliveryViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? PixelDeliveryViewModel())
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading && viewModel.devices.isEmpty {
                    ProgressView("Refreshing dashboard...")
                        .listRowBackground(NRDesign.ColorToken.appBackground)
                }

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(NRDesign.ColorToken.error)
                        .listRowBackground(NRDesign.ColorToken.appBackground)
                }

                if viewModel.devices.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Pixel devices",
                        systemImage: "iphone",
                        description: Text("Open the Pixel app to see account sync activity here.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 28)
                } else {
                    Section("Devices") {
                        ForEach(viewModel.devices) { device in
                            PixelDeliveryDeviceRow(device: device)
                        }
                    }

                    Section("Synced to Device") {
                        SyncedHistoryPanel(
                            deviceName: viewModel.devices.first?.deviceName,
                            jobs: viewModel.succeededJobs,
                            isRefreshing: viewModel.isLoading && !viewModel.succeededJobs.isEmpty,
                            isLoadingMore: viewModel.isLoadingMoreSucceededJobs,
                            onReachJob: { job in
                                await viewModel.loadMoreSucceededJobsIfNeeded(currentJob: job)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(NRDesign.ColorToken.appBackground)
                    }
                }

                if let lastRefreshDate = viewModel.lastRefreshDate {
                    Section {
                        Text("Last refreshed \(lastRefreshDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(NRDesign.ColorToken.secondaryText)
                    }
                    .listRowBackground(NRDesign.ColorToken.appBackground)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Pixel")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh dashboard")
                }
            }
            .task {
                viewModel.startPolling()
            }
            .onDisappear { viewModel.stopPolling() }
            .refreshable {
                await viewModel.refresh()
            }
            .nrPageBackground()
        }
    }
}

private struct SyncedHistoryPanel: View {
    let deviceName: String?
    let jobs: [AccountSyncSucceededJobDTO]
    let isRefreshing: Bool
    let isLoadingMore: Bool
    let onReachJob: (AccountSyncSucceededJobDTO) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent files confirmed on \(deviceName ?? "the selected device").")
                .font(.caption)
                .foregroundStyle(NRDesign.ColorToken.secondaryText)

            if jobs.isEmpty {
                ContentUnavailableView(
                    "No synced items yet",
                    systemImage: "checkmark.circle",
                    description: Text("This list fills in after Pixel confirms downloads from the backend.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(jobs) { job in
                            SyncedHistoryRow(job: job)
                                .task {
                                    await onReachJob(job)
                                }

                            if job.id != jobs.last?.id {
                                Divider()
                                    .overlay(NRDesign.ColorToken.divider)
                            }
                        }

                        if isLoadingMore {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading more synced items...")
                                    .font(.caption)
                                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                        }
                    }
                }
                .frame(height: 360)
            }

            Text(isRefreshing ? "Refreshing latest synced items..." : "Latest synced items update automatically while sync is active.")
                .font(.caption2)
                .foregroundStyle(NRDesign.ColorToken.secondaryText)
        }
        .padding(14)
        .background(NRDesign.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SyncedHistoryRow: View {
    let job: AccountSyncSucceededJobDTO

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NRDesign.ColorToken.primaryText)
                    .lineLimit(1)

                Text("\(job.mediaType) | \(PixelDeliveryDeviceRow.byteFormatter.string(fromByteCount: job.sizeBytes)) | attempt \(job.attemptNumber)")
                    .font(.caption)
                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(job.deviceName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NRDesign.ColorToken.primaryText)
                    .lineLimit(1)

                Text(job.confirmedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct PixelDeliveryDeviceRow: View {
    let device: AccountSyncDeviceDTO

    fileprivate static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.deviceName)
                        .font(.headline)
                        .foregroundStyle(NRDesign.ColorToken.primaryText)
                        .lineLimit(1)

                    Text(scopeSummary)
                        .font(.caption)
                        .foregroundStyle(NRDesign.ColorToken.secondaryText)
                }

                Spacer(minLength: 8)

                Text(device.currentJob?.displayStateText ?? "Idle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(device.currentJob == nil ? NRDesign.ColorToken.secondaryText : NRDesign.ColorToken.accent)
                    .multilineTextAlignment(.trailing)
            }

            if let currentJob = device.currentJob {
                VStack(alignment: .leading, spacing: 6) {
                    Text(currentJob.fileName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NRDesign.ColorToken.primaryText)
                        .lineLimit(1)

                    if let fraction = currentJob.progressFraction {
                        ProgressView(value: fraction)
                            .tint(NRDesign.ColorToken.accent)
                    } else {
                        ProgressView()
                            .tint(NRDesign.ColorToken.accent)
                    }

                    HStack {
                        Text(currentJob.progressSummaryText)
                            .font(.caption)
                            .foregroundStyle(NRDesign.ColorToken.secondaryText)

                        Spacer()

                        if let heartbeat = currentJob.lastHeartbeatAt ?? device.lastSeenAt {
                            Text("Heartbeat \(heartbeat.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(NRDesign.ColorToken.secondaryText)
                        }
                    }
                }
            } else {
                Text(device.lastSeenAt == nil ? "No active job" : "Waiting for the next job")
                    .font(.subheadline)
                    .foregroundStyle(NRDesign.ColorToken.secondaryText)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(NRDesign.ColorToken.surface)
    }

    private var scopeSummary: String {
        let networkHint = device.wifiOnly ? "Wi-Fi only" : "Any network"
        switch device.syncScope {
        case .AccountUploads:
            return "Account uploads | \(networkHint)"
        case .Folder:
            if let scopedFolderId = device.scopedFolderId {
                return "Folder \(scopedFolderId.uuidString.prefix(8)) | \(networkHint)"
            }
            return "Folder sync | \(networkHint)"
        }
    }
}

private extension AccountSyncCurrentJobDTO {
    var progressSummaryText: String {
        if let totalBytes {
            return "\(PixelDeliveryDeviceRow.byteFormatter.string(fromByteCount: progressBytes)) of \(PixelDeliveryDeviceRow.byteFormatter.string(fromByteCount: totalBytes))"
        }

        return "\(PixelDeliveryDeviceRow.byteFormatter.string(fromByteCount: progressBytes)) transferred"
    }
}
