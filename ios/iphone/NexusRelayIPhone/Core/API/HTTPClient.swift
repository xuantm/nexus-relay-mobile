import Foundation

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data?
}

struct HTTPResponse {
    let statusCode: Int
    let headers: [AnyHashable: Any]
    let body: Data
}

struct HTTPUploadProgress: Equatable, Sendable {
    let bytesSent: Int64
    let totalBytes: Int64?
}

typealias HTTPUploadProgressHandler = @Sendable (HTTPUploadProgress) async -> Void

protocol HTTPClient {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
    func uploadFile(
        _ request: HTTPRequest,
        fileURL: URL,
        progress: HTTPUploadProgressHandler?
    ) async throws -> HTTPResponse
    func clearCSRFToken()
}

extension HTTPClient {
    func uploadFile(_ request: HTTPRequest, fileURL: URL) async throws -> HTTPResponse {
        try await uploadFile(request, fileURL: fileURL, progress: nil)
    }
}

final class SystemHTTPClient: HTTPClient {
    private let baseURL: URL
    private let sessionStore: SessionStore
    private let csrfProvider: CSRFTokenProvider
    private let controlSession: URLSession
    private let uploadSession: URLSession
    private let cookieStore: SessionCookieStore
    private let uploadDelegate: SessionDelegateRouter
    private let controlDelegate: SessionDelegateRouter
    private var activeRefreshTask: Task<Bool, Error>?
    private var activeRefreshId: UUID?
    private let refreshLock = NSLock()


    init(
        baseURL: URL,
        sessionStore: SessionStore,
        csrfProvider: CSRFTokenProvider,
        controlSession: URLSession,
        uploadSession: URLSession,
        cookieStore: SessionCookieStore? = nil,
        uploadDelegate: SessionDelegateRouter,
        controlDelegate: SessionDelegateRouter
    ) {
        self.baseURL = baseURL
        self.sessionStore = sessionStore
        self.csrfProvider = csrfProvider
        self.controlSession = controlSession
        self.uploadSession = uploadSession
        self.cookieStore = cookieStore ?? SessionCookieStore(
            storage: controlSession.configuration.httpCookieStorage
        )
        self.uploadDelegate = uploadDelegate
        self.controlDelegate = controlDelegate
    }

    /// Convenience init for tests. Recreates URLSession with a delegate router
    /// so that MockURLProtocol tests correctly fire delegate callbacks.
    convenience init(
        baseURL: URL,
        sessionStore: SessionStore,
        csrfProvider: CSRFTokenProvider,
        controlSession: URLSession,
        cookieStore: SessionCookieStore? = nil
    ) {
        let controlDelegate = SessionDelegateRouter()
        // Must recreate session to attach the delegate!
        let delegatedSession = URLSession(configuration: controlSession.configuration, delegate: controlDelegate, delegateQueue: nil)
        
        self.init(
            baseURL: baseURL,
            sessionStore: sessionStore,
            csrfProvider: csrfProvider,
            controlSession: delegatedSession,
            uploadSession: delegatedSession,
            cookieStore: cookieStore,
            uploadDelegate: controlDelegate,
            controlDelegate: controlDelegate
        )
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        return try await sendWithRetry(request, fileURL: nil)
    }

    func uploadFile(
        _ request: HTTPRequest,
        fileURL: URL,
        progress: HTTPUploadProgressHandler?
    ) async throws -> HTTPResponse {
        return try await sendWithRetry(request, fileURL: fileURL, progress: progress)
    }

    func clearCSRFToken() {
        csrfProvider.clearToken()
        cookieStore.clearCSRFCookies(for: baseURL)
    }

    private func sendWithRetry(
        _ request: HTTPRequest,
        fileURL: URL?,
        progress: HTTPUploadProgressHandler? = nil,
        isRetry: Bool = false
    ) async throws -> HTTPResponse {
        var urlRequest = try await prepareRequest(request)
        if fileURL != nil {
            urlRequest.timeoutInterval = 90.0
        }
        let response: HTTPResponse

        var progressRelay: UploadProgressRelay?

        do {
            if let fileURL = fileURL {
                let relay = UploadProgressRelay(progress: progress)
                progressRelay = relay
                
                let timeoutSeconds = 3600.0 // File uploads can take a long time
                let task = self.uploadSession.uploadTask(with: urlRequest, fromFile: fileURL)
                let (data, urlResponse): (Data, URLResponse) = try await withNetworkTimeout(seconds: timeoutSeconds) {
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { continuation in
                            self.uploadDelegate.register(taskIdentifier: task.taskIdentifier, continuation: continuation, progressRelay: relay)
                            task.resume()
                        }
                    } onCancel: {
                        task.cancel()
                    }
                }
                
                await relay.drain()
                let httpResponse = urlResponse as? HTTPURLResponse
                    ?? HTTPURLResponse(url: urlRequest.url ?? baseURL, statusCode: 0, httpVersion: nil, headerFields: nil)!
                response = HTTPResponse(statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields, body: data)
            } else {
                let timeoutSeconds = urlRequest.timeoutInterval + 30.0
                let task = self.controlSession.dataTask(with: urlRequest)
                let (data, urlResponse): (Data, URLResponse) = try await withNetworkTimeout(seconds: timeoutSeconds) {
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { continuation in
                            self.controlDelegate.register(taskIdentifier: task.taskIdentifier, continuation: continuation, progressRelay: nil)
                            task.resume()
                        }
                    } onCancel: {
                        task.cancel()
                    }
                }
                
                let httpResponse = urlResponse as? HTTPURLResponse
                    ?? HTTPURLResponse(url: urlRequest.url ?? baseURL, statusCode: 0, httpVersion: nil, headerFields: nil)!
                response = HTTPResponse(statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields, body: data)
            }
        } catch {
            await progressRelay?.drain()
            let nsError = error as NSError
            if let fileURL = fileURL, !isRetry,
               (nsError.domain == NSURLErrorDomain &&
                (nsError.code == NSURLErrorCannotParseResponse ||
                 nsError.code == NSURLErrorNetworkConnectionLost ||
                 nsError.code == NSURLErrorTimedOut)) {
                // Connection was reset or timed out (often due to server rejecting request early on 401)
                // Proactively attempt to refresh the token and retry the upload
                if let refreshSuccess = try? await performRefresh(), refreshSuccess {
                    return try await sendWithRetry(request, fileURL: fileURL, progress: progress, isRetry: true)
                }
            }
            throw error
        }

        saveCookies(for: baseURL)

        if response.statusCode == 401 && !isRetry && request.path != "api/auth/refresh" && request.path != "api/auth/login" {
            let refreshSuccess = try await performRefresh()
            if refreshSuccess {
                // Retry once
                return try await sendWithRetry(request, fileURL: fileURL, progress: progress, isRetry: true)
            }
        }

        // If CSRF expired/invalid (often returns 400 or 403), retry once with forced fresh CSRF
        if (response.statusCode == 400 || response.statusCode == 403) && !isRetry && isUnsafeMethod(request.method) && request.path != "api/auth/csrf" {
            clearCSRFToken()
            return try await sendWithRetry(request, fileURL: fileURL, progress: progress, isRetry: true)
        }

        return response
    }

    private func prepareRequest(_ request: HTTPRequest) async throws -> URLRequest {
        let fullURL = try makeURL(path: request.path)
        var urlRequest = URLRequest(url: fullURL)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body

        // Set default headers
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, val) in request.headers {
            urlRequest.setValue(val, forHTTPHeaderField: key)
        }

        // Auto-set Content-Type for JSON body requests when not already provided
        if request.body != nil && urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Sync session cookies to URLSession configuration / cookie storage
        syncCookies(for: baseURL)

        // Add CSRF token for unsafe methods
        if isUnsafeMethod(request.method) && request.path != "api/auth/csrf" {
            let csrfToken = try await csrfProvider.getCSRFToken(baseURL: baseURL, forceRefresh: false)
            urlRequest.setValue(csrfToken, forHTTPHeaderField: "X-NexusRelay-CSRF")
        }

        return urlRequest
    }

    private func makeURL(path: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = pieces.first.map(String.init) ?? ""
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestPath = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let combinedPath = [basePath, requestPath].filter { !$0.isEmpty }.joined(separator: "/")

        components.percentEncodedPath = "/" + combinedPath
        components.percentEncodedQuery = pieces.count > 1 ? String(pieces[1]) : nil

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        return url
    }

    private func isUnsafeMethod(_ method: String) -> Bool {
        let upper = method.uppercased()
        return upper == "POST" || upper == "PUT" || upper == "DELETE"
    }

    private func syncCookies(for url: URL) {
        if let session = sessionStore.currentSession {
            cookieStore.replaceSessionCookies(session.cookies, for: url)
        } else {
            cookieStore.clearManagedCookies(for: url)
        }
    }

    private func saveCookies(for url: URL) {
        guard let session = sessionStore.currentSession else { return }
        let cookies = cookieStore.sessionCookies(for: url)
        let newSession = AuthSession(
            userId: session.userId,
            username: session.username,
            role: session.role,
            cookies: cookies,
            email: session.email,
            authProvider: session.authProvider
        )
        try? sessionStore.saveSession(newSession)
    }

    private func performRefresh() async throws -> Bool {
        refreshLock.lock()
        if let activeTask = activeRefreshTask {
            refreshLock.unlock()
            return try await activeTask.value
        }

        let refreshId = UUID()
        self.activeRefreshId = refreshId

        let task = Task<Bool, Error> { [weak self] in
            guard let self = self else { return false }
            do {
                guard let session = self.sessionStore.currentSession else { return false }
                
                // Sync cookies first to ensure getting the CSRF token and the refresh request use the current session cookies
                self.syncCookies(for: self.baseURL)
                
                let refreshURL = self.baseURL.appendingPathComponent("api/auth/refresh")
                var refreshRequest = URLRequest(url: refreshURL)
                refreshRequest.httpMethod = "POST"

                // Fetch new CSRF
                if let csrf = try? await self.csrfProvider.getCSRFToken(baseURL: self.baseURL, forceRefresh: true) {
                    refreshRequest.setValue(csrf, forHTTPHeaderField: "X-NexusRelay-CSRF")
                }

                let task = self.controlSession.dataTask(with: refreshRequest)
                let (_, response): (Data, URLResponse) = try await withNetworkTimeout(seconds: 45.0) {
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { continuation in
                            self.controlDelegate.register(taskIdentifier: task.taskIdentifier, continuation: continuation, progressRelay: nil)
                            task.resume()
                        }
                    } onCancel: {
                        task.cancel()
                    }
                }
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let success = statusCode == 200
                
                if success {
                    if let httpResponse = response as? HTTPURLResponse {
                        self.saveCookies(from: httpResponse)
                    }
                    self.clearCSRFToken()
                } else if statusCode == 401 || statusCode == 403 {
                    self.clearSessionArtifacts()
                }
                
                self.refreshLock.lock()
                if self.activeRefreshId == refreshId {
                    self.activeRefreshTask = nil
                    self.activeRefreshId = nil
                }
                self.refreshLock.unlock()
                
                return success
            } catch {
                self.refreshLock.lock()
                if self.activeRefreshId == refreshId {
                    self.activeRefreshTask = nil
                    self.activeRefreshId = nil
                }
                self.refreshLock.unlock()
                throw error
            }
        }

        self.activeRefreshTask = task
        refreshLock.unlock()

        return try await task.value
    }

    private func saveCookies(from response: HTTPURLResponse) {
        cookieStore.storeResponseCookies(from: response, for: baseURL)

        saveCookies(for: baseURL)
    }

    private func clearSessionArtifacts() {
        try? sessionStore.clearSession()
        cookieStore.clearManagedCookies(for: baseURL)
        csrfProvider.clearToken()
    }
}

final class UploadProgressRelay: @unchecked Sendable {
    private let progress: HTTPUploadProgressHandler?
    private let lock = NSLock()
    private var pendingEvent: HTTPUploadProgress?
    private var activeTask: Task<Void, Never>?

    init(progress: HTTPUploadProgressHandler?) {
        self.progress = progress
    }

    func report(_ event: HTTPUploadProgress) {
        guard let progress else { return }

        lock.lock()
        pendingEvent = event
        if activeTask == nil {
            activeTask = Task {
                var currentEvent: HTTPUploadProgress?
                
                self.lock.lock()
                currentEvent = self.pendingEvent
                self.pendingEvent = nil
                self.lock.unlock()
                
                while let ev = currentEvent {
                    await progress(ev)
                    
                    self.lock.lock()
                    currentEvent = self.pendingEvent
                    self.pendingEvent = nil
                    if currentEvent == nil {
                        self.activeTask = nil
                    }
                    self.lock.unlock()
                }
            }
        }
        lock.unlock()
    }

    func drain() async {
        var currentTask: Task<Void, Never>?
        lock.lock()
        currentTask = activeTask
        lock.unlock()

        await currentTask?.value
    }
}

final class SessionDelegateRouter: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    struct TaskState {
        let continuation: CheckedContinuation<(Data, URLResponse), Error>
        let progressRelay: UploadProgressRelay?
        var responseData = Data()
        var urlResponse: URLResponse?
    }

    private let lock = NSLock()
    private var tasks: [Int: TaskState] = [:]

    func register(taskIdentifier: Int, continuation: CheckedContinuation<(Data, URLResponse), Error>, progressRelay: UploadProgressRelay?) {
        lock.lock()
        tasks[taskIdentifier] = TaskState(continuation: continuation, progressRelay: progressRelay)
        lock.unlock()
    }

    // MARK: - URLSessionTaskDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        lock.lock()
        let relay = tasks[task.taskIdentifier]?.progressRelay
        lock.unlock()

        let totalBytes = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : nil
        relay?.report(HTTPUploadProgress(bytesSent: totalBytesSent, totalBytes: totalBytes))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard var state = tasks.removeValue(forKey: task.taskIdentifier) else {
            lock.unlock()
            return
        }
        lock.unlock()

        if let error = error {
            state.continuation.resume(throwing: error)
        } else if let response = state.urlResponse {
            state.continuation.resume(returning: (state.responseData, response))
        } else {
            let fallbackError = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
            state.continuation.resume(throwing: fallbackError)
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        tasks[dataTask.taskIdentifier]?.responseData.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        tasks[dataTask.taskIdentifier]?.urlResponse = response
        lock.unlock()
        completionHandler(.allow)
    }
}

private func withNetworkTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw URLError(.timedOut)
        }

        guard let result = try await group.next() else {
            throw URLError(.timedOut)
        }
        group.cancelAll()
        return result
    }
}

