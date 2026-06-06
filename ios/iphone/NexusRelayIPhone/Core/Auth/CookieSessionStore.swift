import Foundation

protocol SessionStore: AnyObject {
    var currentSession: AuthSession? { get }
    func saveSession(_ session: AuthSession) throws
    func loadSession() -> AuthSession?
    func clearSession() throws
}

final class CookieSessionStore: SessionStore {
    private let keychain: KeychainStore
    private let account = "current_session"
    private(set) var currentSession: AuthSession?

    init(keychain: KeychainStore = SystemKeychainStore()) {
        self.keychain = keychain
        self.currentSession = loadSession()
    }

    func saveSession(_ session: AuthSession) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        try keychain.save(data, account: account)
        self.currentSession = session
    }

    func loadSession() -> AuthSession? {
        do {
            guard let data = try keychain.load(account: account) else {
                return nil
            }
            let decoder = JSONDecoder()
            let session = try decoder.decode(AuthSession.self, from: data)
            return session
        } catch {
            return nil
        }
    }

    func clearSession() throws {
        try keychain.delete(account: account)
        self.currentSession = nil
    }
}
