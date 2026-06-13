import Foundation

struct ExportedItem: Sendable {
    let record: UploadLedgerRecord
    let stagedFileURL: URL
    let actualSizeBytes: Int64
}
