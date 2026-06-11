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
                if viewModel.isLoading {
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
                await viewModel.refresh()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .nrPageBackground()
        }
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
