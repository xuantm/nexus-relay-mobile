import UIKit
@testable import NexusRelayIPhone

final class FakeThumbnailProvider: PhotoThumbnailProvider {
    var requestedIds: [String] = []

    func thumbnail(forAssetLocalIdentifier id: String, targetSize: CGSize) async -> UIImage? {
        requestedIds.append(id)
        return UIImage(systemName: "photo")
    }
}
