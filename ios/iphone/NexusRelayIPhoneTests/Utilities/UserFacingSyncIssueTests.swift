import Foundation
import XCTest
@testable import NexusRelayIPhone

final class UserFacingSyncIssueTests: XCTestCase {
    func testMapsAuthenticationErrorsToSignInRequired() {
        XCTAssertEqual(
            UserFacingSyncIssue.from(error: APIError.requestFailed(statusCode: 401, message: "Unauthorized")),
            .signInRequired
        )
        XCTAssertEqual(
            UserFacingSyncIssue.from(error: APIError.requestFailed(statusCode: 403, message: "Forbidden")),
            .signInRequired
        )
    }

    func testMapsConnectivityAndServerErrors() {
        XCTAssertEqual(
            UserFacingSyncIssue.from(error: SyncError.cellularConnectionBlocked),
            .waitingForWiFi
        )
        let issue = UserFacingSyncIssue.from(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        if case .waitingForConnection = issue {
            // pass
        } else {
            XCTFail("Expected .waitingForConnection")
        }
        XCTAssertEqual(
            UserFacingSyncIssue.from(error: APIError.requestFailed(statusCode: 503, message: "Backend unavailable")),
            .serverUnavailable
        )
    }

    func testNormalizesStoredMessagesForQueueRows() {
        XCTAssertEqual(
            UserFacingSyncIssue.fromStoredMessage("Failed to get current user"),
            .signInRequired
        )
        let storedIssue = UserFacingSyncIssue.fromStoredMessage("The Internet connection appears to be offline.")
        if case .waitingForConnection = storedIssue {
            // pass
        } else {
            XCTFail("Expected .waitingForConnection")
        }
        XCTAssertEqual(
            UserFacingSyncIssue.fromStoredMessage("iCloud download required but network access is disabled."),
            .needsICloudDownload
        )
    }
}
