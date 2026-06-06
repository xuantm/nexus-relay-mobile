import PhotoKit
import SwiftUI
import UIKit

protocol PhotoThumbnailProvider {
    func thumbnail(forAssetLocalIdentifier id: String, targetSize: CGSize) async -> UIImage?
}

final class PhotoKitThumbnailProvider: PhotoThumbnailProvider {
    func thumbnail(forAssetLocalIdentifier id: String, targetSize: CGSize) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
