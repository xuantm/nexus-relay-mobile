import XCTest
@testable import NexusRelayIPhone

final class AuthCallbackURLTests: XCTestCase {
    func testParseSuccessURL() {
        let url = URL(string: "nexusrelay://auth/success?code=xyz123")!
        let result = AuthCallbackURL.parse(url)
        XCTAssertEqual(result, .success(code: "xyz123"))
    }
    
    func testParsePendingURL() {
        let url = URL(string: "nexusrelay://auth/pending")!
        let result = AuthCallbackURL.parse(url)
        XCTAssertEqual(result, .pending)
    }
    
    func testParseDeniedURL() {
        let url = URL(string: "nexusrelay://auth/denied?reason=not_approved")!
        let result = AuthCallbackURL.parse(url)
        XCTAssertEqual(result, .denied(reason: "not_approved"))
    }
    
    func testParseDeniedURLWithoutReason() {
        let url = URL(string: "nexusrelay://auth/denied")!
        let result = AuthCallbackURL.parse(url)
        XCTAssertEqual(result, .denied(reason: nil))
    }
    
    func testParseInvalidScheme() {
        let url = URL(string: "http://auth/success?code=123")!
        let result = AuthCallbackURL.parse(url)
        XCTAssertEqual(result, .invalid)
    }
    
    func testParseInvalidHost() {
        let url = URL(string: "nexusrelay://login/success?code=123")!
        let result = AuthCallbackURL.parse(url)
        XCTAssertEqual(result, .invalid)
    }
    
    func testParseInvalidPath() {
        let url = URL(string: "nexusrelay://auth/login?code=123")!
        let result = AuthCallbackURL.parse(url)
        XCTAssertEqual(result, .invalid)
    }
    
    func testParseMissingCode() {
        let url = URL(string: "nexusrelay://auth/success")!
        let result = AuthCallbackURL.parse(url)
        XCTAssertEqual(result, .invalid)
    }
}
