import XCTest
@testable import NexusRelayIPhone

final class SetupChecklistModelTests: XCTestCase {
    func testChecklistRowsExposeUserFacingLabels() {
        let rows = SetupChecklistRow.makeRows(
            serverURL: "https://relay.example.com",
            username: "xuan",
            photosStatus: .authorized,
            destinationFolderName: "iPhone Uploads"
        )

        XCTAssertEqual(rows.map(\.title), ["Server", "Sign in", "Photos Access", "Destination Folder"])
        XCTAssertEqual(rows[0].subtitle, "relay.example.com")
        XCTAssertEqual(rows[1].subtitle, "xuan")
        XCTAssertEqual(rows[2].subtitle, "Full access")
        XCTAssertEqual(rows[3].subtitle, "iPhone Uploads")
    }
}
