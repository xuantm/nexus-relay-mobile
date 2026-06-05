import Foundation
import Photos

final class PhotoKitAssetExporter: AssetExporter {
    func exportOriginalResource(
        candidate: PhotoAssetCandidate,
        outputURL: URL,
        allowNetworkAccess: Bool
    ) async throws {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [candidate.assetLocalIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            throw ExportError.assetNotFound
        }

        let resources = PHAssetResource.assetResources(for: asset)
        let targetType: PHAssetResourceType
        
        switch candidate.resourceKind {
        case .image:
            targetType = .photo
        case .video:
            targetType = .video
        case .livePhotoVideo:
            targetType = .pairedVideo
        }

        guard let resource = resources.first(where: { $0.type == targetType }) else {
            throw ExportError.resourceNotFound
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowNetworkAccess
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            try? FileManager.default.removeItem(at: outputURL)
            
            PHAssetResourceManager.default().writeData(for: resource, toFile: outputURL, options: options) { error in
                if let error = error {
                    let nsError = error as NSError
                    // System errors indicating network is needed (e.g. PHPhotosErrorNetworkAccessRequired)
                    if nsError.domain == "PHPhotosErrorDomain" && (nsError.code == 3053 || nsError.code == 3153) {
                        continuation.resume(throwing: ExportError.networkAccessRequired)
                    } else {
                        try? FileManager.default.removeItem(at: outputURL)
                        continuation.resume(throwing: ExportError.writeFailed(error.localizedDescription))
                    }
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
