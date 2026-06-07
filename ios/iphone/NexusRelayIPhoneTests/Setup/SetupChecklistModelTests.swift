import XCTest
@testable import NexusRelayIPhone

final class SetupChecklistModelTests: XCTestCase {
    func testChecklistRowsExposeUserFacingLabels() {
        let rows = SetupChecklistRow.makeRows(
            isSignedIn: true,
            userEmail: "xuan",
            photosStatus: .authorized,
            destinationFolderName: "iPhone Uploads"
        )

        XCTAssertEqual(rows.map(\.title), ["Sign in", "Photos Access", "Destination"])
        XCTAssertEqual(rows[0].subtitle, "xuan")
        XCTAssertEqual(rows[1].subtitle, "Full access")
        XCTAssertEqual(rows[2].subtitle, "iPhone Uploads")
    }

    func testChecklistMarksUnsignedAccountAsPending() {
        let rows = SetupChecklistRow.makeRows(
            isSignedIn: false,
            userEmail: nil,
            photosStatus: .authorized,
            destinationFolderName: "iPhone Uploads"
        )

        XCTAssertEqual(rows[0].subtitle, "Google account")
        XCTAssertEqual(rows[0].state, .pending)
    }
}
