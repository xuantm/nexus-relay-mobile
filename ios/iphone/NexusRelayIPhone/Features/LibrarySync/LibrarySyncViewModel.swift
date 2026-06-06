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

@MainActor
final class LibrarySyncViewModel: ObservableObject {
    @Published var summary = LibrarySyncSummary(uploaded: 0, waiting: 0, failed: 0, active: 0)
    @Published var activeStatus: ActiveSyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?
    @Published var requiresSignInRepair = false
    @Published var mosaicImages: [UIImage] = []

    private let syncStatusViewModel: SyncStatusViewModel
    private let thumbnailProvider: PhotoThumbnailProvider
    private var cancellables = Set<AnyCancellable>()

    init(
        syncStatusViewModel: SyncStatusViewModel = SyncStatusViewModel(),
        thumbnailProvider: PhotoThumbnailProvider = PhotoKitThumbnailProvider()
    ) {
        self.syncStatusViewModel = syncStatusViewModel
        self.thumbnailProvider = thumbnailProvider
        refreshFromSyncViewModel()

        syncStatusViewModel.$queuedCount
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        syncStatusViewModel.$uploadedCount
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        syncStatusViewModel.$failedCount
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        syncStatusViewModel.$exportingCount
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        syncStatusViewModel.$uploadingCount
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        syncStatusViewModel.$activeStatus
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        syncStatusViewModel.$lastSyncDate
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        syncStatusViewModel.$errorMessage
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        syncStatusViewModel.$requiresSignInRepair
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
    }

    func refreshFromSyncViewModel() {
        summary = LibrarySyncSummary(
            uploaded: syncStatusViewModel.uploadedCount,
            waiting: syncStatusViewModel.queuedCount,
            failed: syncStatusViewModel.failedCount,
            active: syncStatusViewModel.exportingCount + syncStatusViewModel.uploadingCount
        )
        activeStatus = syncStatusViewModel.activeStatus
        lastSyncDate = syncStatusViewModel.lastSyncDate
        errorMessage = syncStatusViewModel.errorMessage
        requiresSignInRepair = syncStatusViewModel.requiresSignInRepair
    }

    func loadMosaicImages() async {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 5
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        
        var images: [UIImage] = []
        for i in 0..<assets.count {
            let asset = assets.object(at: i)
            if let img = await thumbnailProvider.thumbnail(forAssetLocalIdentifier: asset.localIdentifier, targetSize: CGSize(width: 200, height: 200)) {
                images.append(img)
            }
        }
        self.mosaicImages = images
    }

    func syncNow() async {
        await syncStatusViewModel.syncNow()
        refreshFromSyncViewModel()
        await loadMosaicImages()
    }

    func pauseSync() {
        syncStatusViewModel.pauseSync()
        refreshFromSyncViewModel()
    }

    func reconcile() async {
        await syncStatusViewModel.reconcile()
        refreshFromSyncViewModel()
        await loadMosaicImages()
    }
}
