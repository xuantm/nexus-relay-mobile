import Foundation
import Photos
import UniformTypeIdentifiers

final class PhotoKitPhotoLibraryClient: PhotoLibraryClient {
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
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let fetchResult = PHAsset.fetchAssets(with: options)
        
        fetchResult.enumerateObjects { asset, _, _ in
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
                
                // Extract size and original filename
                var fileSize: Int64? = nil
                if let sizeVal = res.value(forKey: "fileSize") as? NSNumber {
                    fileSize = sizeVal.int64Value
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
                    resourceFileSize: fileSize
                )
                
                candidates.append(candidate)
            }
        }
        
        return candidates
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
