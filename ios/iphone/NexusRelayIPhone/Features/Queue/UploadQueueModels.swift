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
    let ledgerStatus: UploadLedgerStatus
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
        self.ledgerStatus = record.status
        self.status = record.uploadStatus
        self.lastError = record.lastError
        self.statusText = Self.statusText(for: record)
        self.progressFraction = Self.progressFraction(for: record.status)
        self.canRetry = record.status == .failed
    }

    private static func statusText(for record: UploadLedgerRecord) -> String {
        switch record.uploadStatus {
        case .Pending:
            return "Pending"
        case .Uploading:
            return "Uploading"
        case .Uploaded:
            return "Uploaded"
        case .Failed:
            return "Failed"
        }
    }

    private static func progressFraction(for status: UploadLedgerStatus) -> Double {
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
        return UploadPolicy.nexusRelayDefault.route(forFileSize: sizeBytes).displayName
    }

    var lastErrorText: String? {
        guard let lastError, !lastError.isEmpty else { return nil }
        return UserFacingSyncIssue.fromStoredMessage(lastError)?.message ?? lastError
    }
}
