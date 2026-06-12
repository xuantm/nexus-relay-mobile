import Foundation

struct UploadProgressTelemetrySnapshot: Equatable {
    let activeUploadedBytes: Int64
    let activeTotalBytes: Int64
    let bytesPerSecond: Double?
    let estimatedSecondsRemaining: Double?
}

actor UploadProgressTracker {
    private struct Sample {
        let bytesSent: Int64
        let totalBytes: Int64
        let date: Date
    }

    private var latestByRecord: [String: Sample] = [:]
    private var previousSample: Sample?
    private var latestSample: Sample?

    func resetSession() {
        latestByRecord.removeAll()
        previousSample = nil
        latestSample = nil
    }

    func recordUploadProgress(recordId: String, bytesSent: Int64, totalBytes: Int64, at date: Date = Date()) {
        let sample = Sample(bytesSent: bytesSent, totalBytes: totalBytes, date: date)
        latestByRecord[recordId] = sample

        if let latestSample, date.timeIntervalSince(latestSample.date) > 0 {
            previousSample = latestSample
        }
        latestSample = sample
    }

    func snapshot(remainingBytes: Int64) -> UploadProgressTelemetrySnapshot {
        let activeUploadedBytes = latestByRecord.values.reduce(Int64(0)) { $0 + $1.bytesSent }
        let activeTotalBytes = latestByRecord.values.reduce(Int64(0)) { $0 + $1.totalBytes }
        let speed = currentBytesPerSecond()
        let eta = speed.flatMap { $0 > 0 ? Double(max(remainingBytes, 0)) / $0 : nil }

        return UploadProgressTelemetrySnapshot(
            activeUploadedBytes: activeUploadedBytes,
            activeTotalBytes: activeTotalBytes,
            bytesPerSecond: speed,
            estimatedSecondsRemaining: eta
        )
    }

    private func currentBytesPerSecond() -> Double? {
        guard let previousSample, let latestSample else {
            return nil
        }

        let elapsed = latestSample.date.timeIntervalSince(previousSample.date)
        guard elapsed > 0 else {
            return nil
        }

        let deltaBytes = latestSample.bytesSent - previousSample.bytesSent
        guard deltaBytes >= 0 else {
            return nil
        }

        return Double(deltaBytes) / elapsed
    }
}
