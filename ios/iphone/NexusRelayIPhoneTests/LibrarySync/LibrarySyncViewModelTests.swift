import XCTest
import UIKit
@testable import NexusRelayIPhone

final class FakeThumbnailProvider: PhotoThumbnailProvider {
    var requestedIds: [String] = []

    func thumbnail(forAssetLocalIdentifier id: String, targetSize: CGSize) async -> UIImage? {
        requestedIds.append(id)
        return UIImage(systemName: "photo")
    }
}

@MainActor
final class LibrarySyncSummaryTests: XCTestCase {
    func testSummaryComputesProgress() {
        let summary = LibrarySyncSummary(uploaded: 842, waiting: 319, failed: 3, active: 6)

        XCTAssertEqual(summary.progressPercentText, "72% uploaded")
        XCTAssertEqual(summary.summaryText, "842 uploaded · 319 waiting · 3 need attention")
        XCTAssertEqual(summary.progressFraction, 842.0 / 1170.0, accuracy: 0.001)
    }

    func testEmptySummaryDoesNotDivideByZero() {
        let summary = LibrarySyncSummary(uploaded: 0, waiting: 0, failed: 0, active: 0)

        XCTAssertEqual(summary.progressPercentText, "0% uploaded")
        XCTAssertEqual(summary.progressFraction, 0)
    }
}

final class LibrarySyncDashboardStateTests: XCTestCase {
    func testDashboardStateFormatsMockupMetrics() {
        let state = LibrarySyncDashboardState(
            progressPercentText: "68%",
            progressLabelText: "Uploaded",
            statusText: "Uploading",
            progressFraction: 0.68,
            etaText: "18 min left",
            speedText: "12 MB/s",
            remainingText: "1.8 GB",
            scannedText: "1,164",
            exportingText: "2",
            uploadingText: "2",
            uploadedText: "842",
            waitingText: "319",
            activeText: "2",
            failedText: "1",
            nextBatchText: "Next batch: 42 photos | 7 videos",
            nextBatchDetailText: "Est. 18 min - 195 MB",
            lastSyncedText: "Last synced: Today, 8:32 AM | Session healthy",
            safeToCloseTitle: "Safe to close app: Yes",
            safeToCloseSubtitle: "Sync will continue in the background",
            canPause: true,
            primaryActionTitle: "Pause Sync"
        )

        XCTAssertEqual(state.statusText, "Uploading")
        XCTAssertEqual(state.nextBatchText, "Next batch: 42 photos | 7 videos")
        XCTAssertTrue(state.canPause)
    }
}

