import XCTest
@testable import NexusRelayIPhone

final class SmoothProgressModelTests: XCTestCase {
    func testProgressClampsBetweenZeroAndOne() {
        var model = SmoothProgressModel()

        model.updateTarget(-1)
        XCTAssertEqual(model.targetProgress, 0)
        XCTAssertEqual(model.displayedProgress, 0)

        model.updateTarget(2)
        XCTAssertEqual(model.targetProgress, 1)
        XCTAssertEqual(model.displayedProgress, 1)
    }

    func testDisplayedProgressDoesNotJumpBackwardDuringActiveUpload() {
        var model = SmoothProgressModel()
        model.updateTarget(0.7)

        model.updateTarget(0.5, allowBackward: false)

        XCTAssertEqual(model.targetProgress, 0.7)
        XCTAssertEqual(model.displayedProgress, 0.7)
    }

    func testDisplayedProgressCanResetWhenBackwardUpdatesAreAllowed() {
        var model = SmoothProgressModel()
        model.updateTarget(0.8)

        model.updateTarget(0.2, allowBackward: true)

        XCTAssertEqual(model.targetProgress, 0.2)
        XCTAssertEqual(model.displayedProgress, 0.2)
    }
}
