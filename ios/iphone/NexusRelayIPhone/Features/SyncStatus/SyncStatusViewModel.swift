import Foundation
import SwiftUI

enum ActiveSyncStatus: String, Equatable {
    case idle = "Idle"
    case scanning = "Scanning"
    case exporting = "Exporting"
    case uploading = "Uploading"
    case pausing = "Pausing"
    case error = "Error"
}

struct SyncStatusSnapshot: Equatable {
    let queuedCount: Int
    let uploadedCount: Int
    let failedCount: Int
    let exportingCount: Int
    let uploadingCount: Int
    let activeStatus: ActiveSyncStatus
    let lastSyncDate: Date?
    let errorMessage: String?
    let requiresSignInRepair: Bool

    static let empty = SyncStatusSnapshot(
        queuedCount: 0,
        uploadedCount: 0,
        failedCount: 0,
        exportingCount: 0,
        uploadingCount: 0,
        activeStatus: .idle,
        lastSyncDate: nil,
        errorMessage: nil,
        requiresSignInRepair: false
    )
}

@MainActor
final class SyncStatusViewModel: ObservableObject {
    @Published var queuedCount = 0
    @Published var uploadedCount = 0
    @Published var failedCount = 0
    @Published var exportingCount = 0
    @Published var uploadingCount = 0
    
    @Published var serverURLString = ""
    @Published var folderName = ""
    @Published var activeStatus: ActiveSyncStatus = .idle
    @Published var lastSyncDate: Date? = nil
    @Published var errorMessage: String? = nil
    @Published var requiresSignInRepair = false
    @Published var isLoggedOut = false
    @Published private(set) var statusSnapshot: SyncStatusSnapshot = .empty
    @Published private(set) var dashboardRuntimeSnapshot: SyncDashboardRuntimeSnapshot = .empty
    
    private let settingsStore: SettingsStore
    private var orchestrator: SyncOrchestrator?
    private var reconciliationService: ReconciliationService?
    private var ledger: UploadLedger?
    private let uploadProgressTracker = UploadProgressTracker()
    private var latestScannedAssetCount: Int?
    
    init(settingsStore: SettingsStore = UserDefaultsSettingsStore()) {
        self.settingsStore = settingsStore
        initializeServices()
    }
    
    func initializeServices() {
        let settings = settingsStore.settings
        guard let url = settings.backendBaseURL else { return }
        self.serverURLString = url.absoluteString
        self.folderName = settings.destinationFolderName
        
        let sessionStore = CookieSessionStore(keychain: SystemKeychainStore())
        let runtime = AuthSessionRuntime(baseURL: url, sessionStore: sessionStore)
        let apiClient = runtime.apiClient
        
        let dbURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ledger.sqlite")
        var isCorrupt = false
        let ledger = LedgerFactory.createOrRecoverLedger(dbURL: dbURL, isCorrupted: &isCorrupt)
        self.ledger = ledger
        
        let scanner = PhotoKitPhotoLibraryClient()
        let exporter = PhotoKitAssetExporter()
        let tempStore = SystemTemporaryFileStore()
        let engine = SystemUploadEngine(apiClient: apiClient, progressTracker: uploadProgressTracker)
        
        self.orchestrator = SystemSyncOrchestrator(
            apiClient: apiClient,
            photosScanner: scanner,
            ledger: ledger,
            exporter: exporter,
            tempFileStore: tempStore,
            uploadEngine: engine,
            settingsStore: settingsStore,
            onScanCompleted: { [weak self] count in
                await MainActor.run {
                    self?.latestScannedAssetCount = count
                }
            }
        )
        
        self.reconciliationService = ReconciliationService(
            apiClient: apiClient,
            photosScanner: scanner,
            ledger: ledger
        )
        
        Task {
            await refreshCounts()
        }
    }
    
    func refreshCounts() async {
        guard let ledger = ledger else { return }
        do {
            let counts = try await ledger.getLedgerCounts()
            self.queuedCount = counts.queued
            self.uploadedCount = counts.uploaded
            self.failedCount = counts.failed
            self.exportingCount = counts.exporting
            self.uploadingCount = counts.uploading
            
            // Adjust active status dynamically if syncing
            if activeStatus != .idle && activeStatus != .error && activeStatus != .pausing {
                if counts.uploading > 0 {
                    activeStatus = .uploading
                } else if counts.exporting > 0 {
                    activeStatus = .exporting
                }
            }
            
            let dashboardSummary = try await ledger.getDashboardSummary(nextBatchLimit: 50)
            let telemetry = await uploadProgressTracker.snapshot(remainingBytes: dashboardSummary.remainingBytes)
            dashboardRuntimeSnapshot = SyncDashboardRuntimeSnapshot(
                ledgerSummary: dashboardSummary,
                telemetry: telemetry,
                scannedAssetCount: latestScannedAssetCount
            )
            
            publishSnapshot()
        } catch {
            print("Failed to get ledger counts: \(error)")
        }
    }
    
    func syncNow() async {
        guard let orchestrator = orchestrator else {
            errorMessage = "Sync orchestrator not initialized"
            activeStatus = .error
            publishSnapshot()
            return
        }
        
        await uploadProgressTracker.resetSession()
        latestScannedAssetCount = nil
        
        errorMessage = nil
        requiresSignInRepair = false
        activeStatus = .scanning
        publishSnapshot()
        
        let pollingTask = Task {
            while activeStatus != .idle && activeStatus != .error && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await refreshCounts()
            }
        }
        
        do {
            _ = try await orchestrator.startSync()
            lastSyncDate = Date()
            activeStatus = .idle
            publishSnapshot()
        } catch {
            let issue = UserFacingSyncIssue.from(error: error)
            errorMessage = issue.message
            requiresSignInRepair = issue.requiresRepairAction
            activeStatus = .error
            publishSnapshot()
        }
        
        pollingTask.cancel()
        await refreshCounts()
    }

    func pauseSync() {
        guard activeStatus == .scanning || activeStatus == .exporting || activeStatus == .uploading else {
            return
        }

        orchestrator?.cancelSync()
        activeStatus = .pausing
        publishSnapshot()
    }
    
    func reconcile() async {
        guard let reconciliationService = reconciliationService,
              let folderId = settingsStore.settings.destinationFolderId else {
            errorMessage = "Reconciliation service not initialized or folder not set"
            activeStatus = .error
            publishSnapshot()
            return
        }
        
        errorMessage = nil
        requiresSignInRepair = false
        activeStatus = .scanning
        publishSnapshot()
        
        do {
            try await reconciliationService.reconcile(folderId: folderId)
            lastSyncDate = Date()
            activeStatus = .idle
            publishSnapshot()
        } catch {
            let issue = UserFacingSyncIssue.from(error: error)
            errorMessage = issue.message
            requiresSignInRepair = issue.requiresRepairAction
            activeStatus = .error
            publishSnapshot()
        }
        
        await refreshCounts()
    }
    
    func logout() {
        let sessionStore = CookieSessionStore(keychain: SystemKeychainStore())
        if let url = settingsStore.settings.backendBaseURL {
            let runtime = AuthSessionRuntime(baseURL: url, sessionStore: sessionStore)
            runtime.clearAuthArtifacts()
        } else {
            try? sessionStore.clearSession()
        }
        
        settingsStore.settings = .defaults
        
        // Explicitly clear references to trigger deinit / database close before file removal
        self.orchestrator = nil
        self.reconciliationService = nil
        self.ledger = nil
        
        let dbURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ledger.sqlite")
        try? FileManager.default.removeItem(at: dbURL)
        
        self.serverURLString = ""
        self.folderName = ""
        self.queuedCount = 0
        self.uploadedCount = 0
        self.failedCount = 0
        self.exportingCount = 0
        self.uploadingCount = 0
        self.activeStatus = .idle
        self.lastSyncDate = nil
        self.errorMessage = nil
        self.requiresSignInRepair = false
        publishSnapshot()
        
        self.isLoggedOut = true
    }

    private func publishSnapshot() {
        statusSnapshot = SyncStatusSnapshot(
            queuedCount: queuedCount,
            uploadedCount: uploadedCount,
            failedCount: failedCount,
            exportingCount: exportingCount,
            uploadingCount: uploadingCount,
            activeStatus: activeStatus,
            lastSyncDate: lastSyncDate,
            errorMessage: errorMessage,
            requiresSignInRepair: requiresSignInRepair
        )
    }
}
