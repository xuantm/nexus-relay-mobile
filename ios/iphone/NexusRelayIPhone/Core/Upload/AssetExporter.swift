import Foundation

enum ExportError: Error, LocalizedError {
    case assetNotFound
    case resourceNotFound
    case networkAccessRequired
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetNotFound: return "Photos asset not found."
        case .resourceNotFound: return "Asset resource not found."
        case .networkAccessRequired: return "iCloud download required but network access is disabled."
        case .writeFailed(let msg): return "Export write failed: \(msg)"
        }
    }
}

protocol AssetExporter {
    func exportOriginalResource(
        candidate: PhotoAssetCandidate,
        outputURL: URL,
        allowNetworkAccess: Bool
    ) async throws
}
