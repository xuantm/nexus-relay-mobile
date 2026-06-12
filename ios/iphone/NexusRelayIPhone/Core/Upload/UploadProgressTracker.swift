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

    private struct GlobalSample {
        let totalBytesSent: Int64
        let date: Date
    }

    private var latestByRecord: [String: Sample] = [:]
    private var globalHistory: [GlobalSample] = []

    func resetSession() {
        latestByRecord.removeAll()
        globalHistory.removeAll()
    }

    func recordUploadProgress(recordId: String, bytesSent: Int64, totalBytes: Int64, at date: Date = Date()) {
        let sample = Sample(bytesSent: bytesSent, totalBytes: totalBytes, date: date)
        latestByRecord[recordId] = sample

        let totalSent = latestByRecord.values.reduce(Int64(0)) { $0 + $1.bytesSent }
        globalHistory.append(GlobalSample(totalBytesSent: totalSent, date: date))
        
        let windowLimit = date.addingTimeInterval(-3.0)
        globalHistory.removeAll { $0.date < windowLimit }
    }

    func snapshot(remainingBytes: Int64, at date: Date = Date()) -> UploadProgressTelemetrySnapshot {
        let windowLimit = date.addingTimeInterval(-3.0)
        globalHistory.removeAll { $0.date < windowLimit }

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
        guard globalHistory.count >= 2 else {
            return nil
        }
        guard let first = globalHistory.first, let last = globalHistory.last else {
            return nil
        }
        let elapsed = last.date.timeIntervalSince(first.date)
        guard elapsed > 0.1 else {
            return nil
        }
        let deltaBytes = last.totalBytesSent - first.totalBytesSent
        guard deltaBytes >= 0 else {
            return nil
        }
        return Double(deltaBytes) / elapsed
    }
}
