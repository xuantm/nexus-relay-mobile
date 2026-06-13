import Foundation

actor BoundedAsyncBuffer {
    private let maxCapacity: Int
    private let maxBytes: Int64
    
    private var buffer: [ExportedItem] = []
    private var currentBytes: Int64 = 0
    private var isFinished = false
    
    private var waitingProducers: [CheckedContinuation<Void, Never>] = []
    private var waitingConsumers: [CheckedContinuation<ExportedItem?, Never>] = []
    
    init(maxCapacity: Int = 32, maxBytes: Int64 = 1_000_000_000) { // 1GB default
        self.maxCapacity = maxCapacity
        self.maxBytes = maxBytes
    }
    
    var count: Int {
        buffer.count
    }
    
    var totalBytes: Int64 {
        currentBytes
    }
    
    func push(_ item: ExportedItem) async {
        if isFinished { return }
        
        // Backpressure: suspend if we've hit either capacity limit
        if buffer.count >= maxCapacity || currentBytes >= maxBytes {
            await withCheckedContinuation { continuation in
                waitingProducers.append(continuation)
            }
            // By the time we resume, there should be space (unless finished)
            if isFinished { return }
        }
        
        buffer.append(item)
        currentBytes += item.actualSizeBytes
        
        // Wake up ONE consumer if any are waiting
        if !waitingConsumers.isEmpty {
            let consumerContinuation = waitingConsumers.removeFirst()
            let poppedItem = buffer.removeFirst()
            currentBytes -= poppedItem.actualSizeBytes
            
            // Re-evaluate waiting producers since we just freed up space
            resumeProducersIfPossible()
            
            consumerContinuation.resume(returning: poppedItem)
        }
    }
    
    func pop() async -> ExportedItem? {
        if !buffer.isEmpty {
            let item = buffer.removeFirst()
            currentBytes -= item.actualSizeBytes
            
            resumeProducersIfPossible()
            
            return item
        }
        
        if isFinished {
            return nil
        }
        
        // Wait for an item
        return await withCheckedContinuation { continuation in
            waitingConsumers.append(continuation)
        }
    }
    
    func finish() {
        isFinished = true
        
        // Resume any waiting consumers with nil so they can exit
        for consumer in waitingConsumers {
            consumer.resume(returning: nil)
        }
        waitingConsumers.removeAll()
        
        // Resume any waiting producers so they can exit gracefully
        for producer in waitingProducers {
            producer.resume()
        }
        waitingProducers.removeAll()
    }
    
    private func resumeProducersIfPossible() {
        // As long as we have space, resume waiting producers
        while !waitingProducers.isEmpty && buffer.count < maxCapacity && currentBytes < maxBytes {
            let producerContinuation = waitingProducers.removeFirst()
            producerContinuation.resume()
        }
    }
}
