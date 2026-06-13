import Foundation

struct LibrarySyncDashboardState: Equatable {
    let progressPercentText: String
    let progressLabelText: String
    let statusText: String
    let progressFraction: Double
    let etaText: String
    let speedText: String
    let remainingText: String
    let scannedText: String
    let uploadingText: String
    let uploadedText: String
    let waitingText: String
    let activeText: String
    let failedText: String
    let nextBatchText: String
    let nextBatchDetailText: String
    let lastSyncedText: String
    let safeToCloseTitle: String
    let safeToCloseSubtitle: String
    let canPause: Bool
    let primaryActionTitle: String

    static let empty = LibrarySyncDashboardState(
        progressPercentText: "0%",
        progressLabelText: "Uploaded",
        statusText: "Ready",
        progressFraction: 0,
        etaText: "Estimating",
        speedText: "-- MB/s",
        remainingText: "0 MB",
        scannedText: "0",
        uploadingText: "0",
        uploadedText: "0",
        waitingText: "0",
        activeText: "0",
        failedText: "0",
        nextBatchText: "Next batch: Nothing waiting",
        nextBatchDetailText: "Est. -- - 0 MB",
        lastSyncedText: "Last synced: Not yet | Session healthy",
        safeToCloseTitle: "Safe to close app: Yes",
        safeToCloseSubtitle: "Sync will continue in the background",
        canPause: false,
        primaryActionTitle: "Start Sync"
    )
}

enum LibrarySyncDashboardFormatter {
    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func speed(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else {
            return "-- MB/s"
        }

        let megabytes = bytesPerSecond / 1_000_000
        if megabytes < 0.1 {
            return "-- MB/s"
        } else if megabytes < 10 {
            return String(format: "%.1f MB/s", megabytes)
        } else {
            return "\(Int(megabytes.rounded())) MB/s"
        }
    }

    static func eta(_ seconds: Double?) -> String {
        guard let seconds else {
            return "Estimating"
        }

        if seconds < 30 {
            return "< 1 min left"
        }
        let minutes = Int((seconds / 60).rounded())
        return "\(max(minutes, 1)) min left"
    }
}
