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
/// - When `Security.framework` is not available (Linux CI in this project's
///   sandbox) the credentials are persisted to a plaintext file under the
///   temporary directory. This path is clearly gated and is not used on
///   macOS builds.
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
        return loadFromPlaintextFile() ?? .unauthenticated
        #endif
    }

    /// Drops any stored credentials.
    public static func clearStored() {
        #if canImport(Security)
        clearKeychain()
        #else
        clearPlaintextFile()
        #endif
    }

    /// Persists `info` to the platform secret store. Exposed so callers
    /// (e.g., after a successful OAuth handshake) can store credentials
    /// they obtained out-of-band.
    public static func store(_ info: BfmeWorkshopAuthInfo) throws {
        #if canImport(Security)
        try storeInKeychain(info)
        #else
        try storeInPlaintextFile(info)
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

    // MARK: - Plaintext fallback (Linux CI only)

    private static var plaintextURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bfme-workshop-credentials.json")
    }

    private static func storeInPlaintextFile(_ info: BfmeWorkshopAuthInfo) throws {
        let data = try JSONEncoder().encode(info)
        try data.write(to: plaintextURL, options: .atomic)
    }

    private static func loadFromPlaintextFile() -> BfmeWorkshopAuthInfo? {
        guard let data = try? Data(contentsOf: plaintextURL) else { return nil }
        return try? JSONDecoder().decode(BfmeWorkshopAuthInfo.self, from: data)
    }

    private static func clearPlaintextFile() {
        try? FileManager.default.removeItem(at: plaintextURL)
    }
}
