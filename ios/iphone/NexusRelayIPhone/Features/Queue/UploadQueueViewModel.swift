import Foundation

@MainActor
final class UploadQueueViewModel: ObservableObject {
    @Published var selectedSegment: UploadQueueSegment = .all
    @Published var items: [UploadQueueItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let ledger: UploadLedger

    init(ledger: UploadLedger? = nil) {
        if let ledger {
            self.ledger = ledger
        } else {
            let dbURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ledger.sqlite")
            var isCorrupt = false
            self.ledger = LedgerFactory.createOrRecoverLedger(dbURL: dbURL, isCorrupted: &isCorrupt)
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let records = try await ledger.listQueueRecords(filter: selectedSegment.ledgerFilter, limit: 100)
            items = records.map(UploadQueueItem.init(record:))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
     }

     func retryAll() async {
         let ids = items.filter(\.canRetry).map(\.id)
         guard !ids.isEmpty else { return }
         do {
             try await ledger.retryFailed(ids: ids)
             await load()
         } catch {
             errorMessage = error.localizedDescription
         }
     }
}
