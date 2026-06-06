import Foundation

enum UploadQueueSegment: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case failed = "Failed"

    var id: String { rawValue }

    var ledgerFilter: UploadQueueFilter {
        switch self {
        case .all: return .all
        case .active: return .active
        case .failed: return .failed
        }
    }
}

struct UploadQueueItem: Identifiable, Equatable {
    let id: String
    let assetLocalIdentifier: String
    let filename: String
    let resourceKind: PhotoResourceKind
    let sizeBytes: Int64?
    let status: UploadStatus
    let lastError: String?
    let statusText: String
    let progressFraction: Double
    let canRetry: Bool

    init(record: UploadLedgerRecord) {
        self.id = record.id
        self.assetLocalIdentifier = record.assetLocalIdentifier
        self.filename = record.originalFilename
        self.resourceKind = record.resourceKind
        self.sizeBytes = record.sizeBytes
        self.status = record.status
        self.lastError = record.lastError
        self.statusText = Self.statusText(for: record)
        self.progressFraction = Self.progressFraction(for: record.status)
        self.canRetry = record.status == .failed
    }

    private static func statusText(for record: UploadLedgerRecord) -> String {
        if record.status == .failed, let error = record.lastError, !error.isEmpty {
            return UserFacingSyncIssue.fromStoredMessage(error)?.message ?? error
        }

        switch record.status {
        case .discovered: return "Waiting to upload"
        case .exporting: return "Preparing"
        case .readyToUpload: return "Ready"
        case .uploading: return "Uploading"
        case .uploaded: return "Uploaded"
        case .synced: return "Uploaded"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }

    private static func progressFraction(for status: UploadStatus) -> Double {
        switch status {
        case .discovered: return 0
        case .exporting: return 0.18
        case .readyToUpload: return 0.32
        case .uploading: return 0.72
        case .uploaded, .synced: return 1
        case .failed, .skipped: return 0
        }
    }

    var sizeText: String {
        guard let sizeBytes else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var uploadModeText: String {
        guard let sizeBytes else { return "Determined during upload" }
        return sizeBytes > UploadPolicy.nexusRelayDefault.streamThresholdBytes ? "Chunked upload" : "Direct upload"
    }

    var lastErrorText: String? {
        guard let lastError, !lastError.isEmpty else { return nil }
        return UserFacingSyncIssue.fromStoredMessage(lastError)?.message ?? lastError
    }
}
