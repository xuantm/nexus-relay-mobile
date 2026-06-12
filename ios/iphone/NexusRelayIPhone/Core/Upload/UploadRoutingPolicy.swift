import Foundation

enum UploadRoute: String, Equatable {
    case multipartStream
    case resumableStream
    case chunked

    var displayName: String {
        switch self {
        case .multipartStream:
            return "Direct multipart upload"
        case .resumableStream:
            return "Direct resumable upload"
        case .chunked:
            return "Chunked upload"
        }
    }

    var usesStreamEndpoint: Bool {
        switch self {
        case .multipartStream, .resumableStream:
            return true
        case .chunked:
            return false
        }
    }
}
