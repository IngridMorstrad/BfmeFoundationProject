import Foundation
#if canImport(Security)
import Security
#endif

/// Port of `BfmeWorkshopAuthManager.cs`. Does the SHA-256 double-hash the
/// backend expects, then stores the returned credentials.
///
/// Token persistence:
/// - On macOS the credentials are stored in the user keychain via
///   `SecItemAdd` / `SecItemUpdate` / `SecItemCopyMatching`. This is the
///   production path.
/// - On non-Darwin platforms (Linux CI) we refuse durable persistence
///   (review bullet #8). The previous implementation wrote to
///   `/tmp/bfme-workshop-credentials.json` with default umask which made
///   the file world-readable. The replacement keeps an in-memory stub so
///   tests exercising the load/store/clear contract still pass, but no
///   credential data ever touches disk on a non-Darwin host.
public enum BfmeWorkshopAuthManager {
    public static let keychainService = "com.bfmefoundation.workshop.credentials"
    public static let keychainAccount = "current-user"

    /// POSTs the credentials, throws on failure with a message that matches
    /// the C# exception payload ("user_not_found", "wrong_password",
    /// "error", "suspended*").
    public static func authenticate(email: String, password: String) async throws -> BfmeWorkshopAuthInfo {
        let passwordHash = sha256Hex(sha256Hex(password))
        let result: [String] = (try? await HttpUtils.getJSON(
            authInfo: .unauthenticated,
            apiEndpointPath: "auth/login",
            parameters: ["email": email, "password": passwordHash]
        )) ?? ["", "", ""]

        if result.count >= 1 {
            if result[0] == "user_not_found" { throw AuthError.userNotFound }
            if result[0] == "wrong_password" { throw AuthError.wrongPassword }
            if result[0] == "error" { throw AuthError.generic }
            if result[0].hasPrefix("suspended") { throw AuthError.suspended(result[0]) }
        }
        guard result.count >= 3,
              let data = result[2].data(using: .utf8),
              let info = try? JSONDecoder().decode(BfmeWorkshopAuthInfo.self, from: data) else {
            throw AuthError.generic
        }
        try store(info)
        return info
    }

    /// Pulls the stored token tuple from the platform secret store.
    /// Returns `BfmeWorkshopAuthInfo.unauthenticated` when nothing is stored.
    public static func loadStored() -> BfmeWorkshopAuthInfo {
        #if canImport(Security)
        return loadFromKeychain() ?? .unauthenticated
        #else
        return inMemoryStore.load() ?? .unauthenticated
        #endif
    }

    /// Drops any stored credentials.
    public static func clearStored() {
        #if canImport(Security)
        clearKeychain()
        #else
        inMemoryStore.clear()
        #endif
    }

    /// Persists `info` to the platform secret store. Exposed so callers
    /// (e.g., after a successful OAuth handshake) can store credentials
    /// they obtained out-of-band.
    public static func store(_ info: BfmeWorkshopAuthInfo) throws {
        #if canImport(Security)
        try storeInKeychain(info)
        #else
        inMemoryStore.store(info)
        #endif
    }

    public enum AuthError: Error, Equatable, CustomStringConvertible {
        case userNotFound
        case wrongPassword
        case generic
        case suspended(String)

        public var description: String {
            switch self {
            case .userNotFound: return "user_not_found"
            case .wrongPassword: return "wrong_password"
            case .generic: return "error"
            case .suspended(let raw): return raw
            }
        }
    }

    // MARK: - SHA-256

    static func sha256Hex(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var hasher = SHA256()
        hasher.update(bytes)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Keychain backend (macOS)

    #if canImport(Security)
    private static func storeInKeychain(_ info: BfmeWorkshopAuthInfo) throws {
        let data = try JSONEncoder().encode(info)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw AuthError.generic
            }
        } else if status != errSecSuccess {
            throw AuthError.generic
        }
    }

    private static func loadFromKeychain() -> BfmeWorkshopAuthInfo? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(BfmeWorkshopAuthInfo.self, from: data)
    }

    private static func clearKeychain() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
    #endif

    // MARK: - Non-Darwin fallback (process-lifetime, no disk I/O)

    /// Process-lifetime in-memory stand-in used when `Security.framework`
    /// isn't available (Linux CI). The previous implementation wrote to
    /// `/tmp/bfme-workshop-credentials.json` with default umask, which was
    /// world-readable. This replacement is explicitly tests-only: nothing
    /// persists across processes, and no credential bytes ever land on
    /// disk. See review bullet #8.
    final class InMemoryCredentialStore: @unchecked Sendable {
        private var value: BfmeWorkshopAuthInfo?
        private let lock = NSLock()

        func load() -> BfmeWorkshopAuthInfo? {
            lock.lock(); defer { lock.unlock() }
            return value
        }

        func store(_ info: BfmeWorkshopAuthInfo) {
            lock.lock(); defer { lock.unlock() }
            value = info
        }

        func clear() {
            lock.lock(); defer { lock.unlock() }
            value = nil
        }
    }

    static let inMemoryStore = InMemoryCredentialStore()
}
