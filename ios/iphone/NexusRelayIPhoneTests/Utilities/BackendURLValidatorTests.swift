import XCTest
@testable import NexusRelayIPhone

final class BackendURLValidatorTests: XCTestCase {
    func testAcceptsHttpAndHttpsURLs() {
        XCTAssertTrue(BackendURLValidator.isValid("https://relay.example.com"))
        XCTAssertTrue(BackendURLValidator.isValid("http://relay.example.com"))
    }

    func testRejectsRelativeOrUnsupportedURLs() {
        XCTAssertFalse(BackendURLValidator.isValid("relay.example.com"))
        XCTAssertFalse(BackendURLValidator.isValid("ftp://relay.example.com"))
        XCTAssertFalse(BackendURLValidator.isValid(""))
    }
}
