import XCTest
@testable import NexusRelayIPhone

final class MockPixelDeliveryAPI: NexusRelayAPI {
    var dashboardResult: Result<AccountSyncDashboardDTO, Error> = .success(
        AccountSyncDashboardDTO(
            overview: AccountSyncOverviewDTO(
                completedUploads: 0,
                failedUploads: 0,
                syncedToDevices: 0,
                failedDeviceSyncJobs: 0,
                stalledDeviceSyncJobs: 0,
                activeDeviceSyncJobs: 0,
                activeDevices: 0
            ),
            devices: [],
            failedJobs: [],
            stalledJobs: [],
            failedUploads: []
        )
    )
    var waitForRelease = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func login(username: String, password: String) async throws -> AuthSession { fatalError() }
    func exchangeIosSession(code: String) async throws -> AuthSession { fatalError() }
    func currentUser() async throws -> BrowserAuthResponse { fatalError() }
    func getAccountSyncDashboard() async throws -> AccountSyncDashboardDTO {
        if waitForRelease {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        return try dashboardResult.get()
    }
    func listRootFolders() async throws -> [FolderDTO] { fatalError() }
    func createFolder(name: String, parentId: UUID?) async throws -> FolderDTO { fatalError() }
    func listFolderMedia(folderId: UUID, pageSize: Int, cursor: String?) async throws -> FolderContentDTO { fatalError() }
    func streamUpload(fileURL: URL, fileName: String, folderId: UUID, mimeType: String, fileSize: Int64) async throws -> StreamUploadResponse { fatalError() }
    func initUpload(folderId: UUID, fileName: String, totalSize: Int64, totalChunks: Int) async throws -> InitUploadResponse { fatalError() }
    func uploadChunk(uploadId: UUID, chunkIndex: Int, chunkSize: Int64, chunkFileURL: URL) async throws { fatalError() }
    func completeUpload(uploadId: UUID, fileHash: String?) async throws { fatalError() }
}

@MainActor
final class PixelDeliveryViewModelTests: XCTestCase {
    func testRefreshLoadsDashboardDevicesAndMarksLoadingWhileAwaiting() async throws {
        let api = MockPixelDeliveryAPI()
        api.waitForRelease = true
        api.dashboardResult = .success(
            AccountSyncDashboardDTO(
                overview: AccountSyncOverviewDTO(
                    completedUploads: 12,
                    failedUploads: 0,
                    syncedToDevices: 18,
                    failedDeviceSyncJobs: 0,
                    stalledDeviceSyncJobs: 0,
                    activeDeviceSyncJobs: 1,
                    activeDevices: 1
                ),
                devices: [
                    AccountSyncDeviceDTO(
                        targetId: UUID(uuidString: "2d6c4f66-5be2-4f31-8c2f-02ac2e1a55ee")!,
                        deviceName: "Pixel 8",
                        platform: "Android",
                        enabled: true,
                        wifiOnly: true,
                        syncScope: .AccountUploads,
                        scopedFolderId: nil,
                        lastSeenAt: Date(timeIntervalSince1970: 1_781_168_400),
                        isActive: true,
                        pendingJobs: 0,
                        syncingJobs: 1,
                        stalledJobs: 0,
                        failedJobs: 0,
                        syncedJobs: 18,
                        currentJob: AccountSyncCurrentJobDTO(
                            jobId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                            mediaId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                            fileName: "IMG_1001.HEIC",
                            mimeType: "image/heic",
                            mediaType: "Image",
                            sizeBytes: 4_820_131,
                            attemptNumber: 2,
                            stage: "Downloading",
                            progressBytes: 2_410_065,
                            totalBytes: 4_820_131,
                            claimedAt: Date(timeIntervalSince1970: 1_781_168_100),
                            lastHeartbeatAt: Date(timeIntervalSince1970: 1_781_168_460),
                            leaseExpiresAt: Date(timeIntervalSince1970: 1_781_169_360),
                            workerRunId: "run-1"
                        )
                    )
                ],
                failedJobs: [],
                stalledJobs: [],
                failedUploads: []
            )
        )

        let viewModel = PixelDeliveryViewModel(apiClient: api)
        let refreshTask = Task { await viewModel.refresh() }

        for _ in 0..<20 {
            if viewModel.isLoading {
                break
            }
            await Task.yield()
        }

        XCTAssertTrue(viewModel.isLoading)

        api.release()
        await refreshTask.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.devices.count, 1)
        XCTAssertEqual(viewModel.devices.first?.deviceName, "Pixel 8")
        XCTAssertEqual(viewModel.devices.first?.currentJob?.displayStateText, "Downloading")
        XCTAssertEqual(viewModel.devices.first?.currentJob?.progressFraction, 0.5, accuracy: 0.0001)
        XCTAssertNotNil(viewModel.lastRefreshDate)
    }

    func testRefreshSetsErrorMessageWhenDashboardRequestFails() async throws {
        let api = MockPixelDeliveryAPI()
        api.dashboardResult = .failure(APIError.requestFailed(statusCode: 503, message: "Service Unavailable"))

        let viewModel = PixelDeliveryViewModel(apiClient: api)
        await viewModel.refresh()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.devices.isEmpty)
        XCTAssertEqual(
            viewModel.errorMessage,
            APIError.requestFailed(statusCode: 503, message: "Service Unavailable").localizedDescription
        )
        XCTAssertNil(viewModel.lastRefreshDate)
    }
}
