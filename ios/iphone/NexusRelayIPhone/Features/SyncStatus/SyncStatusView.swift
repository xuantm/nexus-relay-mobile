import SwiftUI

struct SyncStatusView: View {
    @StateObject var viewModel = SyncStatusViewModel()
    var onLogout: () -> Void
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        ZStack {
            // Dark elegant background
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.09, blue: 0.15), Color(red: 0.15, green: 0.18, blue: 0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header Section
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NexusRelay")
                                .font(.system(.title, design: .rounded))
                                .bold()
                                .foregroundColor(.white)
                            Text("Sync Dashboard")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        
                        // Status Indicator Badge
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                                .shadow(color: statusColor, radius: 4)
                            Text(viewModel.activeStatus.rawValue)
                                .font(.system(.caption, design: .rounded))
                                .bold()
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .padding(.top, 20)

                    // Active Operation Status Alert / Staging Alert
                    if viewModel.activeStatus != .idle {
                        activeStatusAlertView
                    }

                    // Connection Info Card
                    connectionInfoCard

                    // Statistics Grid
                    statisticsGrid

                    // Error Box
                    if let error = viewModel.errorMessage {
                        errorCard(error: error)
                    }

                    // Actions Section
                    actionsCard
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            viewModel.initializeServices()
        }
        .onChange(of: viewModel.isLoggedOut) { _, loggedOut in
            if loggedOut {
                onLogout()
            }
        }
    }
    
    private var statusColor: Color {
        switch viewModel.activeStatus {
        case .idle: return .green
        case .scanning: return .blue
        case .exporting: return .cyan
        case .uploading: return .orange
        case .error: return .red
        }
    }
    
    private var activeStatusAlertView: some View {
        HStack(spacing: 12) {
            switch viewModel.activeStatus {
            case .scanning:
                ProgressView()
                    .tint(.blue)
                Text("Preparing assets & scanning library...")
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(.white)
            case .exporting:
                ProgressView()
                    .tint(.cyan)
                Text("Exporting local PhotoKit assets...")
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(.white)
            case .uploading:
                ProgressView()
                    .tint(.orange)
                Text("Uploading files to NexusRelay...")
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(.white)
            default:
                EmptyView()
            }
            Spacer()
        }
        .padding()
        .background(statusColor.opacity(0.12))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor.opacity(0.24), lineWidth: 1)
        )
    }
    
    private var connectionInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundColor(.blue)
                    .font(.title2)
                Text("Connection Details")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            VStack(spacing: 8) {
                HStack {
                    Text("Server URL")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.gray)
                    Spacer()
                    Text(viewModel.serverURLString)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                HStack {
                    Text("Sync Destination")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.gray)
                    Spacer()
                    Text(viewModel.folderName)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.cyan)
                        .bold()
                }
                
                if let lastSync = viewModel.lastSyncDate {
                    HStack {
                        Text("Last Sync")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(dateFormatter.string(from: lastSync))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var statisticsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            statCard(
                title: "Queued",
                value: "\(viewModel.queuedCount)",
                icon: "arrow.up.circle",
                color: .cyan,
                subText: viewModel.exportingCount > 0 ? "\(viewModel.exportingCount) exporting" : "Ready to upload"
            )
            
            statCard(
                title: "Synced",
                value: "\(viewModel.uploadedCount)",
                icon: "checkmark.circle",
                color: .green,
                subText: "Uploaded items"
            )
            
            statCard(
                title: "Failed",
                value: "\(viewModel.failedCount)",
                icon: "exclamationmark.circle",
                color: .red,
                subText: "Will retry later"
            )
            
            statCard(
                title: "Uploading",
                value: "\(viewModel.uploadingCount)",
                icon: "icloud.and.arrow.up",
                color: .orange,
                subText: "Active transfer"
            )
        }
    }
    
    private func statCard(
        title: String,
        value: String,
        icon: String,
        color: Color,
        subText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.headline)
                Spacer()
            }
            
            Text(value)
                .font(.system(.title, design: .rounded))
                .bold()
                .foregroundColor(.white)
            
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.gray)
            
            Text(subText)
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(.gray.opacity(0.8))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func errorCard(error: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Error Details")
                    .font(.system(.subheadline, design: .rounded))
                    .bold()
                    .foregroundColor(.white)
                Text(error)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.16), lineWidth: 1)
        )
    }
    
    private var actionsCard: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await viewModel.syncNow()
                }
            } label: {
                HStack {
                    if viewModel.activeStatus == .scanning || viewModel.activeStatus == .exporting || viewModel.activeStatus == .uploading {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 5)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Sync Now")
                        .bold()
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(viewModel.activeStatus == .scanning || viewModel.activeStatus == .exporting || viewModel.activeStatus == .uploading)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.reconcile()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Reconcile")
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .disabled(viewModel.activeStatus == .scanning || viewModel.activeStatus == .exporting || viewModel.activeStatus == .uploading)

                Button(role: .destructive) {
                    viewModel.logout()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Logout")
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.24), lineWidth: 1)
                    )
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
