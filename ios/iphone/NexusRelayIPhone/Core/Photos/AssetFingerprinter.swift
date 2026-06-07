import Foundation
import CryptoKit

struct AssetFingerprinter {
    static func generateFingerprint(candidate: PhotoAssetCandidate) -> String {
        let creationDateStr: String
        if let creationDate = candidate.creationDate {
            let formatter = ISO8601DateFormatter()
            creationDateStr = formatter.string(from: creationDate)
        } else {
            creationDateStr = ""
        }
        
        let sizeStr = candidate.resourceFileSize.map { String($0) } ?? ""
        
        let input = candidate.assetLocalIdentifier
            + candidate.resourceKind.rawValue
            + creationDateStr
            + candidate.originalFilename
            + sizeStr
            
        guard let data = input.data(using: .utf8) else {
            return ""
        }
        
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func getFingerprintSuffix(fingerprint: String) -> String {
        return String(fingerprint.prefix(16))
    }

    static func generateUploadedFilename(candidate: PhotoAssetCandidate, suffix: String) -> String {
        let originalName = candidate.originalFilename
        let fileURL = URL(fileURLWithPath: originalName)
        let ext = fileURL.pathExtension
        
        var baseName = fileURL.deletingPathExtension().lastPathComponent
        
        if baseName.isEmpty {
            baseName = "media"
        }
        
        // Clean __nr- if already exists
        if let nrIndex = baseName.range(of: "__nr-") {
            baseName = String(baseName[..<nrIndex.lowerBound])
        }
        
        // Sanitize base name
        baseName = sanitizeFilename(baseName)
        
        let safeExt = sanitizeFilename(ext)
        
        if safeExt.isEmpty {
            return baseName
        } else {
            return "\(baseName).\(safeExt)"
        }
    }
    
    static func sanitizeFilename(_ name: String) -> String {
        var clean = name
        let charactersToRemove = ["/", "\\", "\"", "'", "\r", "\n"]
        for char in charactersToRemove {
            clean = clean.replacingOccurrences(of: char, with: "")
        }
        return clean
    }
}
