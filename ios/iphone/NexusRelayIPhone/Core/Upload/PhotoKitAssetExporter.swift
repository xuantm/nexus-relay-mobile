import Foundation
import Photos

final class PhotoKitAssetExporter: AssetExporter {
    private let semaphore = DispatchSemaphore(value: 2)
    private let queue = DispatchQueue(label: "com.nexusrelay.iphone.export", attributes: .concurrent)

    func exportOriginalResource(
        candidate: PhotoAssetCandidate,
        outputURL: URL,
        allowNetworkAccess: Bool
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self else { return }
                self.semaphore.wait()
                
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [candidate.assetLocalIdentifier], options: nil)
                guard let asset = fetchResult.firstObject else {
                    self.semaphore.signal()
                    continuation.resume(throwing: ExportError.assetNotFound)
                    return
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
                    self.semaphore.signal()
                    continuation.resume(throwing: ExportError.resourceNotFound)
                    return
                }

                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = allowNetworkAccess
                
                try? FileManager.default.removeItem(at: outputURL)
                
                PHAssetResourceManager.default().writeData(for: resource, toFile: outputURL, options: options) { error in
                    self.semaphore.signal()
                    if let error = error {
                        let nsError = error as NSError
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
}
