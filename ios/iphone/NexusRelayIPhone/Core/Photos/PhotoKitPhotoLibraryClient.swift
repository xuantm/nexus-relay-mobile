import AVFoundation
import Foundation
import Photos
import UniformTypeIdentifiers

final class PhotoKitPhotoLibraryClient: PhotoLibraryClient {
    private let fileSizeResolver: PublicPhotoAssetFileSizeResolver

    init(fileSizeResolver: PublicPhotoAssetFileSizeResolver = PublicPhotoAssetFileSizeResolver()) {
        self.fileSizeResolver = fileSizeResolver
    }

    func authorizationStatus() -> PhotoLibraryAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return mapStatus(status)
    }

    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return mapStatus(status)
    }

    func fetchCandidates(includeVideos: Bool, includeLivePhotoVideo: Bool) async throws -> [PhotoAssetCandidate] {
        guard authorizationStatus() == .authorized || authorizationStatus() == .limited else {
            return []
        }

        var candidates: [PhotoAssetCandidate] = []
        var assets: [PHAsset] = []

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(with: options)
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        for asset in assets {
            if asset.mediaType == .video && !includeVideos {
                continue
            }

            let publicSizes = await resolvePublicFileSizes(for: asset)
            let resources = PHAssetResource.assetResources(for: asset)

            for res in resources {
                let kind: PhotoResourceKind
                if asset.mediaSubtypes.contains(.photoLive) {
                    if res.type == .photo {
                        kind = .image
                    } else if res.type == .pairedVideo && includeLivePhotoVideo {
                        kind = .livePhotoVideo
                    } else {
                        continue
                    }
                } else {
                    if asset.mediaType == .image && res.type == .photo {
                        kind = .image
                    } else if asset.mediaType == .video && res.type == .video && includeVideos {
                        kind = .video
                    } else {
                        continue
                    }
                }

                let originalFilename = res.originalFilename
                let uti = res.uniformTypeIdentifier

                // Get MIME type from UTI
                let mimeType = UTType(uti)?.preferredMIMEType ?? "application/octet-stream"

                let candidate = PhotoAssetCandidate(
                    assetLocalIdentifier: asset.localIdentifier,
                    resourceKind: kind,
                    originalFilename: originalFilename,
                    uniformTypeIdentifier: uti,
                    mimeType: mimeType,
                    creationDate: asset.creationDate,
                    modificationDate: asset.modificationDate,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    durationSeconds: asset.mediaType == .video ? asset.duration : nil,
                    resourceFileSize: publicFileSize(for: kind, sizes: publicSizes)
                )

                candidates.append(candidate)
            }
        }

        return candidates
    }

    private func resolvePublicFileSizes(for asset: PHAsset) async -> ResolvedPublicAssetSizes {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = false
        options.canHandleAdjustmentData = { _ in true }

        let input = await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                continuation.resume(returning: input)
            }
        }

        return ResolvedPublicAssetSizes(
            imageSize: fileSizeResolver.fileSize(forImageFileURL: input?.fullSizeImageURL),
            videoSize: fileSizeResolver.fileSize(forAudiovisualAsset: input?.audiovisualAsset)
        )
    }

    private func publicFileSize(for kind: PhotoResourceKind, sizes: ResolvedPublicAssetSizes) -> Int64? {
        switch kind {
        case .image:
            return sizes.imageSize
        case .video, .livePhotoVideo:
            return sizes.videoSize
        }
    }

    private func mapStatus(_ status: PHAuthorizationStatus) -> PhotoLibraryAuthorizationStatus {
        switch status {
        case .authorized: return .authorized
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}

struct PublicPhotoAssetFileSizeResolver {
    func fileSize(forImageFileURL fileURL: URL?) -> Int64? {
        fileSize(at: fileURL)
    }

    func fileSize(forAudiovisualAsset asset: AVAsset?) -> Int64? {
        guard let urlAsset = asset as? AVURLAsset else {
            return nil
        }

        return fileSize(at: urlAsset.url)
    }

    private func fileSize(at fileURL: URL?) -> Int64? {
        guard let fileURL, fileURL.isFileURL else {
            return nil
        }

        guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else {
            return nil
        }

        if let allocatedSize = values.totalFileAllocatedSize {
            return Int64(allocatedSize)
        }

        if let fileSize = values.fileSize {
            return Int64(fileSize)
        }

        return nil
    }
}

private struct ResolvedPublicAssetSizes {
    let imageSize: Int64?
    let videoSize: Int64?
}
