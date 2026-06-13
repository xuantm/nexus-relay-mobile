import Foundation
import Photos

final class PhotoKitAssetExporter: AssetExporter, @unchecked Sendable {

    private final class RequestHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var _id: PHAssetResourceDataRequestID?
        
        var id: PHAssetResourceDataRequestID? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _id
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _id = newValue
            }
        }
    }

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
        
        try? FileManager.default.removeItem(at: outputURL)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: nil)
        
        let holder = RequestHolder()

        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: resource, toFile: outputURL, options: options, completionHandler: { error in
                    if let error = error {
                        let nsError = error as NSError
                        if Task.isCancelled || nsError.code == NSUserCancelledError || (nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.userCancelled.rawValue) {
                            try? FileManager.default.removeItem(at: outputURL)
                            continuation.resume(throwing: CancellationError())
                        } else if nsError.domain == "PHPhotosErrorDomain" && (nsError.code == 3053 || nsError.code == 3153) {
                            continuation.resume(throwing: ExportError.networkAccessRequired)
                        } else {
                            try? FileManager.default.removeItem(at: outputURL)
                            continuation.resume(throwing: ExportError.writeFailed(error.localizedDescription))
                        }
                    } else {
                        if Task.isCancelled {
                            try? FileManager.default.removeItem(at: outputURL)
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                })
            }
        } onCancel: {
            if let id = holder.id {
                PHAssetResourceManager.default().cancelDataRequest(id)
            }
        }
    }
}
