import Foundation

protocol TemporaryFileStore {
    func getStagedFileURL(recordId: String, fileName: String) throws -> URL
    func deleteStagedFile(recordId: String) throws
    func cleanStaleFiles() throws
}

final class SystemTemporaryFileStore: TemporaryFileStore {
    private let rootTempURL: URL

    init() {
        let tempDir = FileManager.default.temporaryDirectory
        self.rootTempURL = tempDir.appendingPathComponent("com.nexusrelay.iphone.uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootTempURL, withIntermediateDirectories: true)
    }

    func getStagedFileURL(recordId: String, fileName: String) throws -> URL {
        let safeDirName = recordId.replacingOccurrences(of: ":", with: "_")
        let dirURL = rootTempURL.appendingPathComponent(safeDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        return dirURL.appendingPathComponent(fileName)
    }

    func deleteStagedFile(recordId: String) throws {
        let safeDirName = recordId.replacingOccurrences(of: ":", with: "_")
        let dirURL = rootTempURL.appendingPathComponent(safeDirName, isDirectory: true)
        if FileManager.default.fileExists(atPath: filePath(for: dirURL)) {
            try FileManager.default.removeItem(at: dirURL)
        }
    }

    func cleanStaleFiles() throws {
        guard FileManager.default.fileExists(atPath: filePath(for: rootTempURL)) else { return }
        
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        
        let resourceKeys: [URLResourceKey] = [.contentModificationDateKey]
        let enumerator = FileManager.default.enumerator(
            at: rootTempURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsSubdirectoryDescendants]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if let modDate = resourceValues.contentModificationDate, modDate < sevenDaysAgo {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func filePath(for url: URL) -> String {
        if #available(iOS 16.0, *) {
            return url.path(percentEncoded: false)
        } else {
            return url.path
        }
    }
}
