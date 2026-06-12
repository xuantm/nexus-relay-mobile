import Foundation

struct UploadProgressTelemetrySnapshot: Equatable {
    let activeUploadedBytes: Int64
    let activeTotalBytes: Int64
    let bytesPerSecond: Double?
    let estimatedSecondsRemaining: Double?
}

actor UploadProgressTracker {
    private struct Increment {
        let bytes: Int64
        let date: Date
    }

    private struct RecordState {
        var lastBytesSent: Int64
        var totalBytes: Int64
    }

    private var recordStates: [String: RecordState] = [:]
    private var incrementHistory: [Increment] = []
    private var smoothedBytesPerSecond: Double?
    private let emaAlpha: Double = 0.3

    func resetSession() {
        recordStates.removeAll()
        incrementHistory.removeAll()
        smoothedBytesPerSecond = nil
    }

    func recordUploadProgress(recordId: String, bytesSent: Int64, totalBytes: Int64, at date: Date = Date()) {
        let prevBytes = recordStates[recordId]?.lastBytesSent ?? 0
        let delta = bytesSent - prevBytes
        
        recordStates[recordId] = RecordState(lastBytesSent: bytesSent, totalBytes: totalBytes)
        
        if delta > 0 {
            incrementHistory.append(Increment(bytes: delta, date: date))
        }
        
        let windowLimit = date.addingTimeInterval(-3.0)
        incrementHistory.removeAll { $0.date < windowLimit }
    }

    func snapshot(remainingBytes: Int64, at date: Date = Date()) -> UploadProgressTelemetrySnapshot {
        let windowLimit = date.addingTimeInterval(-3.0)
        incrementHistory.removeAll { $0.date < windowLimit }

        let activeUploadedBytes = recordStates.values.reduce(Int64(0)) { $0 + $1.lastBytesSent }
        let activeTotalBytes = recordStates.values.reduce(Int64(0)) { $0 + $1.totalBytes }
        
        let rawSpeed = rawBytesPerSecond(at: date)
        
        // Apply EMA smoothing
        if let raw = rawSpeed {
            if let prev = smoothedBytesPerSecond {
                smoothedBytesPerSecond = emaAlpha * raw + (1 - emaAlpha) * prev
            } else {
                smoothedBytesPerSecond = raw
            }
        } else {
            // If there are no active states or no history has ever been recorded, keep it nil
            if !recordStates.isEmpty {
                if let prev = smoothedBytesPerSecond {
                    smoothedBytesPerSecond = emaAlpha * 0.0 + (1 - emaAlpha) * prev
                } else {
                    smoothedBytesPerSecond = 0.0
                }
            } else {
                smoothedBytesPerSecond = nil
            }
        }
        
        let speed = smoothedBytesPerSecond
        let eta = speed.flatMap { $0 > 0 ? Double(max(remainingBytes, 0)) / $0 : nil }

        return UploadProgressTelemetrySnapshot(
            activeUploadedBytes: activeUploadedBytes,
            activeTotalBytes: activeTotalBytes,
            bytesPerSecond: speed,
            estimatedSecondsRemaining: eta
        )
    }

    private func rawBytesPerSecond(at date: Date) -> Double? {
        guard !incrementHistory.isEmpty else {
            return nil
        }
        
        let totalBytesInWindow = incrementHistory.reduce(Int64(0)) { $0 + $1.bytes }
        
        // Find the oldest sample in the window to calculate elapsed time
        guard let firstSample = incrementHistory.first else {
            return nil
        }
        
        let elapsed = date.timeIntervalSince(firstSample.date)
        guard elapsed > 0.1 else {
            return nil
        }
        
        return Double(totalBytesInWindow) / elapsed
    }
}
