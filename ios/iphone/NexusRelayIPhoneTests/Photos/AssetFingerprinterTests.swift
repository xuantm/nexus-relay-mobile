import AVFoundation
import XCTest
@testable import NexusRelayIPhone

final class AssetFingerprinterTests: XCTestCase {
    func testDeterministicFingerprint() {
        let date = Date(timeIntervalSince1970: 1770000000)
        let candidate = PhotoAssetCandidate(
            assetLocalIdentifier: "test-asset-id-123",
            resourceKind: .image,
            originalFilename: "IMG_1234.HEIC",
            uniformTypeIdentifier: "public.heic",
            mimeType: "image/heic",
            creationDate: date,
            modificationDate: date,
            pixelWidth: 4000,
            pixelHeight: 3000,
            durationSeconds: nil,
            resourceFileSize: 5000000
        )
        
        let fp1 = AssetFingerprinter.generateFingerprint(candidate: candidate)
        let fp2 = AssetFingerprinter.generateFingerprint(candidate: candidate)
        
        XCTAssertEqual(fp1, fp2)
        XCTAssertEqual(fp1.count, 64) // SHA-256 hex length
        
        let suffix = AssetFingerprinter.getFingerprintSuffix(fingerprint: fp1)
        XCTAssertEqual(suffix.count, 16)
    }
    
    func testDifferentSizeDifferentFingerprint() {
        let date = Date(timeIntervalSince1970: 1770000000)
        let candidate1 = PhotoAssetCandidate(
            assetLocalIdentifier: "test-asset-id-123",
            resourceKind: .image,
            originalFilename: "IMG_1234.HEIC",
            uniformTypeIdentifier: "public.heic",
            mimeType: "image/heic",
            creationDate: date,
            modificationDate: date,
            pixelWidth: 4000,
            pixelHeight: 3000,
            durationSeconds: nil,
            resourceFileSize: 5000000
        )
        
        let candidate2 = PhotoAssetCandidate(
            assetLocalIdentifier: "test-asset-id-123",
            resourceKind: .image,
            originalFilename: "IMG_1234.HEIC",
            uniformTypeIdentifier: "public.heic",
            mimeType: "image/heic",
            creationDate: date,
            modificationDate: date,
            pixelWidth: 4000,
            pixelHeight: 3000,
            durationSeconds: nil,
            resourceFileSize: 5000001
        )
        
        let fp1 = AssetFingerprinter.generateFingerprint(candidate: candidate1)
        let fp2 = AssetFingerprinter.generateFingerprint(candidate: candidate2)
        
        XCTAssertNotEqual(fp1, fp2)
    }

    func testUploadedFilenameGeneration() {
        let date = Date(timeIntervalSince1970: 1770000000)
        let candidate = PhotoAssetCandidate(
            assetLocalIdentifier: "ph://A3B123-CD456/L0/001",
            resourceKind: .image,
            originalFilename: "IMG_12/34\\\"' \r\n.HEIC",
            uniformTypeIdentifier: "public.heic",
            mimeType: "image/heic",
            creationDate: date,
            modificationDate: date,
            pixelWidth: 4000,
            pixelHeight: 3000,
            durationSeconds: nil,
            resourceFileSize: 5000000
        )
        
        let fp = AssetFingerprinter.generateFingerprint(candidate: candidate)
        let suffix = AssetFingerprinter.getFingerprintSuffix(fingerprint: fp)
        let uploadedName = AssetFingerprinter.generateUploadedFilename(candidate: candidate, suffix: suffix)
        
        // Final filename should not expose the raw localIdentifier
        XCTAssertFalse(uploadedName.contains("ph://"))
        XCTAssertFalse(uploadedName.contains("A3B123"))
        
        // Final filename should be sanitized of / \ " ' \r \n
        XCTAssertFalse(uploadedName.contains("/"))
        XCTAssertFalse(uploadedName.contains("\\"))
        XCTAssertFalse(uploadedName.contains("\""))
        XCTAssertFalse(uploadedName.contains("'"))
        XCTAssertFalse(uploadedName.contains("\r"))
        XCTAssertFalse(uploadedName.contains("\n"))
        
        XCTAssertTrue(uploadedName.hasSuffix(".HEIC"))
        XCTAssertTrue(uploadedName.contains("__nr-\(suffix)"))
    }
    
    func testUploadedFilenameOverwritesPreviousMarker() {
        let date = Date(timeIntervalSince1970: 1770000000)
        let candidate = PhotoAssetCandidate(
            assetLocalIdentifier: "test-asset",
            resourceKind: .image,
            originalFilename: "IMG_1001__nr-a3f91c0d8e74b210.HEIC",
            uniformTypeIdentifier: "public.heic",
            mimeType: "image/heic",
            creationDate: date,
            modificationDate: date,
            pixelWidth: 4000,
            pixelHeight: 3000,
            durationSeconds: nil,
            resourceFileSize: 5000000
        )
        
        let suffix = "bd02941f22ac9170"
        let uploadedName = AssetFingerprinter.generateUploadedFilename(candidate: candidate, suffix: suffix)
        
        XCTAssertEqual(uploadedName, "IMG_1001__nr-bd02941f22ac9170.HEIC")
    }

    func testPublicFileSizeResolverReadsImageFileURLSize() throws {
        let resolver = PublicPhotoAssetFileSizeResolver()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = Data(repeating: 0xAB, count: 13)

        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertEqual(resolver.fileSize(forImageFileURL: fileURL), 13)
    }

    func testPublicFileSizeResolverReadsAVURLAssetSize() throws {
        let resolver = PublicPhotoAssetFileSizeResolver()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = Data(repeating: 0xCD, count: 21)

        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let asset = AVURLAsset(url: fileURL)
        XCTAssertEqual(resolver.fileSize(forAudiovisualAsset: asset), 21)
    }

    func testPublicFileSizeResolverReturnsNilForRemoteAVURLAsset() {
        let resolver = PublicPhotoAssetFileSizeResolver()
        let remoteAsset = AVURLAsset(url: URL(string: "https://example.com/video.mov")!)

        XCTAssertNil(resolver.fileSize(forAudiovisualAsset: remoteAsset))
    }
}
