import Foundation

struct SmoothProgressModel: Equatable {
    private(set) var targetProgress: Double = 0
    private(set) var displayedProgress: Double = 0

    mutating func updateTarget(_ value: Double, allowBackward: Bool = true) {
        let clamped = min(max(value, 0), 1)
        if !allowBackward && clamped < targetProgress {
            return
        }
        targetProgress = clamped
        displayedProgress = clamped
    }
}
