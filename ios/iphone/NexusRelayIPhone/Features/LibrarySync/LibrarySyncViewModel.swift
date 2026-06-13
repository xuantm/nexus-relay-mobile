import Foundation
import SwiftUI
import UIKit
import Combine
import Photos

struct LibrarySyncSummary: Equatable {
    let uploaded: Int
    let waiting: Int
    let failed: Int
    let active: Int

    var total: Int { uploaded + waiting + failed + active }

    var progressFraction: Double {
        guard total > 0 else { return 0 }
        return Double(uploaded) / Double(total)
    }

    var progressPercentText: String {
        "\(Int((progressFraction * 100).rounded()))% uploaded"
    }

    var summaryText: String {
        "\(uploaded) uploaded · \(waiting) waiting · \(failed) need attention"
    }
}

enum LibraryPreviewMediaType: String, Equatable {
    case image
    case video

    var symbolName: String {
        switch self {
        case .image: return "photo"
        case .video: return "play.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .image: return "Photo"
        case .video: return "Video"
        }
    }
}

struct LibraryPreviewItem: Identifiable {
    let id: String
    let assetLocalIdentifier: String
    let image: UIImage
    let mediaType: LibraryPreviewMediaType
    let creationDate: Date?
    let filename: String?
}

@MainActor
final class LibrarySyncViewModel: ObservableObject {
    @Published var summary = LibrarySyncSummary(uploaded: 0, waiting: 0, failed: 0, active: 0)
    @Published var displayedProgress: Double = 0
    @Published var activeStatus: ActiveSyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?
    @Published var requiresSignInRepair = false
    @Published var dashboard = LibrarySyncDashboardState.empty

    private let syncStatusViewModel: SyncStatusViewModel
    private let thumbnailProvider: PhotoThumbnailProvider
    private let settingsStore: SettingsStore
    private var cancellables = Set<AnyCancellable>()
    private var smoothProgress = SmoothProgressModel()

    init(
        syncStatusViewModel: SyncStatusViewModel? = nil,
        thumbnailProvider: PhotoThumbnailProvider? = nil,
        settingsStore: SettingsStore = UserDefaultsSettingsStore()
    ) {
        let svm = syncStatusViewModel ?? SyncStatusViewModel()
        self.syncStatusViewModel = svm
        self.thumbnailProvider = thumbnailProvider ?? PhotoKitThumbnailProvider()
        self.settingsStore = settingsStore
        refreshFromSyncViewModel()

        svm.$statusSnapshot
            .sink { [weak self] snapshot in self?.refresh(from: snapshot) }
            .store(in: &cancellables)

        svm.$dashboardRuntimeSnapshot
            .sink { [weak self] runtime in self?.refreshDashboard(runtime: runtime) }
            .store(in: &cancellables)
    }

    func refreshFromSyncViewModel() {
        refresh(from: syncStatusViewModel.statusSnapshot)
    }

    private func refresh(from snapshot: SyncStatusSnapshot) {
        let nextSummary = LibrarySyncSummary(
            uploaded: snapshot.uploadedCount,
            waiting: snapshot.queuedCount,
            failed: snapshot.failedCount,
            active: snapshot.exportingCount + snapshot.uploadingCount
        )
        let nextStatus = snapshot.activeStatus

        summary = nextSummary
        activeStatus = nextStatus
        lastSyncDate = snapshot.lastSyncDate
        errorMessage = snapshot.errorMessage
        requiresSignInRepair = snapshot.requiresSignInRepair

        smoothProgress.updateTarget(
            nextSummary.progressFraction,
            allowBackward: nextStatus == .idle || nextStatus == .error
        )
        displayedProgress = smoothProgress.displayedProgress
    }

    private func refreshDashboard(runtime: SyncDashboardRuntimeSnapshot) {
        let counts = runtime.ledgerSummary.counts
        let total = counts.queued + counts.uploaded + counts.failed + counts.exporting + counts.uploading
        let progressFraction = total > 0 ? Double(counts.uploaded) / Double(total) : 0
        let nextBatch = runtime.ledgerSummary.nextBatch
        let nextBatchText = nextBatch.photoCount == 0 && nextBatch.videoCount == 0
            ? "Next batch: Nothing waiting"
            : "Next batch: \(nextBatch.photoCount) photos | \(nextBatch.videoCount) videos"
        let sessionText = requiresSignInRepair ? "Session needs repair" : "Session healthy"
        let lastSynced = lastSyncDate.map { "Last synced: \($0.formatted(date: .abbreviated, time: .shortened)) | \(sessionText)" }
            ?? "Last synced: Not yet | \(sessionText)"

        let isSyncActive = activeStatus == .scanning || activeStatus == .exporting || activeStatus == .uploading
        let speedText = isSyncActive ? LibrarySyncDashboardFormatter.speed(runtime.telemetry.bytesPerSecond) : "-- MB/s"
        let etaText = isSyncActive ? LibrarySyncDashboardFormatter.eta(runtime.telemetry.estimatedSecondsRemaining) : "Estimating"

        dashboard = LibrarySyncDashboardState(
            progressPercentText: "\(Int((progressFraction * 100).rounded()))%",
            progressLabelText: "Uploaded",
            statusText: activeStatus.rawValue,
            progressFraction: progressFraction,
            etaText: etaText,
            speedText: speedText,
            remainingText: LibrarySyncDashboardFormatter.bytes(runtime.ledgerSummary.remainingBytes),
            scannedText: LibrarySyncDashboardFormatter.count(runtime.scannedAssetCount ?? total),
            uploadingText: LibrarySyncDashboardFormatter.count(counts.uploading),
            uploadedText: LibrarySyncDashboardFormatter.count(counts.uploaded),
            waitingText: LibrarySyncDashboardFormatter.count(counts.queued),
            activeText: LibrarySyncDashboardFormatter.count(counts.exporting + counts.uploading),
            failedText: LibrarySyncDashboardFormatter.count(counts.failed),
            nextBatchText: nextBatchText,
            nextBatchDetailText: "Est. \(LibrarySyncDashboardFormatter.eta(runtime.telemetry.estimatedSecondsRemaining).replacingOccurrences(of: " left", with: "")) - \(LibrarySyncDashboardFormatter.bytes(nextBatch.totalBytes))",
            lastSyncedText: lastSynced,
            safeToCloseTitle: requiresSignInRepair ? "Safe to close app: No" : "Safe to close app: Yes",
            safeToCloseSubtitle: requiresSignInRepair ? "Repair sign-in before background sync can continue" : "Sync will continue in the background",
            canPause: activeStatus == .scanning || activeStatus == .exporting || activeStatus == .uploading,
            primaryActionTitle: activeStatus == .scanning || activeStatus == .exporting || activeStatus == .uploading ? "Pause Sync" : "Start Sync"
        )
    }

    func syncNow() async {
        await syncStatusViewModel.syncNow()
        refreshFromSyncViewModel()
    }

    func pauseSync() {
        syncStatusViewModel.pauseSync()
        refreshFromSyncViewModel()
    }

    func reconcile() async {
        await syncStatusViewModel.reconcile()
        refreshFromSyncViewModel()
    }
}
