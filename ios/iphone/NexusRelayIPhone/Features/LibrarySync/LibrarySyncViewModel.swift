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
    @Published var previewItems: [LibraryPreviewItem] = []
    @Published var selectedPreviewItem: LibraryPreviewItem?

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

        svm.$queuedCount
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        svm.$uploadedCount
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        svm.$failedCount
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        svm.$exportingCount
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        svm.$uploadingCount
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        svm.$activeStatus
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        svm.$lastSyncDate
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        svm.$errorMessage
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
        svm.$requiresSignInRepair
            .sink { [weak self] _ in self?.refreshFromSyncViewModel() }
            .store(in: &cancellables)
    }

    func refreshFromSyncViewModel() {
        let nextSummary = LibrarySyncSummary(
            uploaded: syncStatusViewModel.uploadedCount,
            waiting: syncStatusViewModel.queuedCount,
            failed: syncStatusViewModel.failedCount,
            active: syncStatusViewModel.exportingCount + syncStatusViewModel.uploadingCount
        )
        let nextStatus = syncStatusViewModel.activeStatus

        summary = nextSummary
        activeStatus = nextStatus
        lastSyncDate = syncStatusViewModel.lastSyncDate
        errorMessage = syncStatusViewModel.errorMessage
        requiresSignInRepair = syncStatusViewModel.requiresSignInRepair

        smoothProgress.updateTarget(
            nextSummary.progressFraction,
            allowBackward: nextStatus == .idle || nextStatus == .error
        )
        displayedProgress = smoothProgress.displayedProgress
    }

    func loadPreviewItems() async {
        let includeVideos = settingsStore.settings.includeVideos
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 5
        if !includeVideos {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        }
        let assets = PHAsset.fetchAssets(with: options)

        var items: [LibraryPreviewItem] = []
        for i in 0..<assets.count {
            let asset = assets.object(at: i)
            guard asset.mediaType == .image || asset.mediaType == .video else {
                continue
            }
            if asset.mediaType == .video && !includeVideos {
                continue
            }

            if let img = await thumbnailProvider.thumbnail(
                forAssetLocalIdentifier: asset.localIdentifier,
                targetSize: CGSize(width: 280, height: 280)
            ) {
                let resources = PHAssetResource.assetResources(for: asset)
                let filename = resources.first?.originalFilename
                let mediaType: LibraryPreviewMediaType = asset.mediaType == .video ? .video : .image

                items.append(
                    LibraryPreviewItem(
                        id: asset.localIdentifier,
                        assetLocalIdentifier: asset.localIdentifier,
                        image: img,
                        mediaType: mediaType,
                        creationDate: asset.creationDate,
                        filename: filename
                    )
                )
            }
        }

        previewItems = items

        if let selectedPreviewItem, !items.contains(where: { $0.id == selectedPreviewItem.id }) {
            self.selectedPreviewItem = nil
        }
    }

    func syncNow() async {
        await syncStatusViewModel.syncNow()
        refreshFromSyncViewModel()
        await loadPreviewItems()
    }

    func pauseSync() {
        syncStatusViewModel.pauseSync()
        refreshFromSyncViewModel()
    }

    func reconcile() async {
        await syncStatusViewModel.reconcile()
        refreshFromSyncViewModel()
        await loadPreviewItems()
    }
}
