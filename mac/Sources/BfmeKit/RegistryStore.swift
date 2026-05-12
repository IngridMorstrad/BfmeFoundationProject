import Foundation

/// Hive selector modeled on the Win32 registry. We only need the two hives the
/// original BFME tree reaches for: `HKEY_LOCAL_MACHINE` (game install state)
/// and `HKEY_CURRENT_USER` (per-user compatibility layers).
public enum RegistryHive: String, Sendable, Hashable {
    case hklm
    case hkcu
}

/// Typed value container mirroring Win32's `RegistryValueKind`.
public enum RegistryValue: Equatable, Hashable, Sendable {
    case string(String)
    case dword(Int32)
    case qword(Int64)
    case binary(Data)
    case multiString([String])

    public var stringValue: String {
        switch self {
        case .string(let s): return s
        case .dword(let v): return String(v)
        case .qword(let v): return String(v)
        case .binary(let d): return d.base64EncodedString()
        case .multiString(let parts): return parts.joined(separator: "\n")
        }
    }
}

/// Categorization of the `RegistryValueKind` used when setting values through
/// the higher-level managers.
public enum RegistryValueKind: String, Sendable {
    case string
    case dword
    case qword
    case binary
    case multiString
}

/// Thread-safe JSON-backed key-value store that mimics the shape of the
/// Windows registry tree the original C# launcher reads. The on-disk format
/// is a single JSON file under `~/Library/Application Support/BFME Foundation/registry.json`:
///
/// ```
/// {
///   "hklm": {
///     "SOFTWARE\\Electronic Arts\\EA Games\\The Battle for Middle-earth": {
///       "InstallPath": { "type": "string", "value": "/Users/.../BFME" },
///       "Version":     { "type": "dword",  "value": 65539 }
///     }
///   },
///   "hkcu": { ... }
/// }
/// ```
///
/// Writes are atomic (temp file + rename), and every mutation is funneled
/// through an `actor` so cross-task access is serialized.
public actor RegistryStore {
    // MARK: - Test-only base path override

    /// Lets tests point the store at a throw-away directory instead of the
    /// real `~/Library/Application Support`. Setting this to `nil` restores
    /// the default location.
    public static var applicationSupportOverride: URL?

    // MARK: - Shared singleton

    /// The process-wide store. `BfmeRegistryManager` and `BfmeSettingsManager`
    /// route every call through this instance.
    public static let shared = RegistryStore()

    // MARK: - Instance state

    private var loaded: Bool = false
    private var hives: [String: [String: [String: StoredValue]]] = [
        RegistryHive.hklm.rawValue: [:],
        RegistryHive.hkcu.rawValue: [:]
    ]

    public init() {}

    // MARK: - Paths

    public static func baseDirectory(fileManager: FileManager = .default) -> URL {
        if let override = applicationSupportOverride {
            return override
        }
        let home = fileManager.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("BFME Foundation", isDirectory: true)
    }

    public static func storeURL(fileManager: FileManager = .default) -> URL {
        baseDirectory(fileManager: fileManager)
            .appendingPathComponent("registry.json")
    }

    // MARK: - Public API (Win32-style)

    /// Returns `true` if the subkey exists and has any stored values.
    /// Matches the semantics of `Registry.LocalMachine.OpenSubKey(path) != nil`.
    public func openSubKey(hive: RegistryHive, path: String) async -> Bool {
        await ensureLoaded()
        let key = Self.normalize(path)
        return hives[hive.rawValue]?[key] != nil
    }

    /// Creates a subkey if it does not already exist and persists the change.
    /// Corresponds to `Registry.LocalMachine.CreateSubKey(path)`.
    public func createSubKey(hive: RegistryHive, path: String) async throws {
        await ensureLoaded()
        let key = Self.normalize(path)
        if hives[hive.rawValue]?[key] == nil {
            hives[hive.rawValue]?[key] = [:]
            try await persist()
        }
    }

    /// Reads a single value. Returns `nil` when either the subkey or the value
    /// name is missing, matching the Win32 behavior where a missing value
    /// surfaces as `null` back to managed code.
    public func getValue(hive: RegistryHive, path: String, name: String) async -> RegistryValue? {
        await ensureLoaded()
        let key = Self.normalize(path)
        guard let stored = hives[hive.rawValue]?[key]?[name] else { return nil }
        return stored.toRegistryValue()
    }

    /// Writes (or overwrites) a value, creating the subkey as needed. Always
    /// flushes to disk atomically.
    public func setValue(hive: RegistryHive, path: String, name: String, value: RegistryValue) async throws {
        await ensureLoaded()
        let key = Self.normalize(path)
        if hives[hive.rawValue]?[key] == nil {
            hives[hive.rawValue]?[key] = [:]
        }
        hives[hive.rawValue]?[key]?[name] = StoredValue(value: value)
        try await persist()
    }

    /// Deletes a subkey and every subkey whose path begins with
    /// `path\` (the backslash prefix is appended automatically).
    /// Mirrors `Registry.LocalMachine.DeleteSubKeyTree`.
    public func deleteSubKeyTree(hive: RegistryHive, path: String) async throws {
        await ensureLoaded()
        let normalized = Self.normalize(path)
        let prefix = normalized + #"\"#
        guard var hiveMap = hives[hive.rawValue] else { return }
        var removed = false
        if hiveMap.removeValue(forKey: normalized) != nil { removed = true }
        for k in hiveMap.keys where k.hasPrefix(prefix) {
            hiveMap.removeValue(forKey: k)
            removed = true
        }
        hives[hive.rawValue] = hiveMap
        if removed {
            try await persist()
        }
    }

    /// Lists every value name stored under a subkey. Unordered to match Win32.
    public func valueNames(hive: RegistryHive, path: String) async -> [String] {
        await ensureLoaded()
        let key = Self.normalize(path)
        guard let values = hives[hive.rawValue]?[key] else { return [] }
        return Array(values.keys)
    }

    /// Drops every hive back to an empty state and removes the on-disk
    /// backing file. Primarily useful from tests.
    public func reset() async throws {
        hives = [
            RegistryHive.hklm.rawValue: [:],
            RegistryHive.hkcu.rawValue: [:]
        ]
        loaded = true
        let url = Self.storeURL()
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    // MARK: - Persistence

    /// Normalizes a subkey path: trim leading/trailing backslashes and collapse
    /// forward slashes to backslashes so callers can be sloppy.
    static func normalize(_ path: String) -> String {
        var p = path.replacingOccurrences(of: "/", with: #"\"#)
        while p.hasPrefix(#"\"#) { p.removeFirst() }
        while p.hasSuffix(#"\"#) { p.removeLast() }
        return p
    }

    private func ensureLoaded() async {
        if loaded { return }
        loaded = true
        let url = Self.storeURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        guard let parsed = try? JSONDecoder().decode(DiskSchema.self, from: data) else { return }
        hives = [
            RegistryHive.hklm.rawValue: parsed.hklm ?? [:],
            RegistryHive.hkcu.rawValue: parsed.hkcu ?? [:]
        ]
    }

    private func persist() async throws {
        let baseURL = Self.baseDirectory()
        let fm = FileManager.default
        try fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let url = Self.storeURL()

        let schema = DiskSchema(
            hklm: hives[RegistryHive.hklm.rawValue] ?? [:],
            hkcu: hives[RegistryHive.hkcu.rawValue] ?? [:]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(schema)

        // Atomic write: stage into a temp file in the same directory, then
        // replace the destination in one syscall. Foundation's
        // `Data.write(to:options:.atomic)` delivers that contract on both
        // Darwin and Linux.
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - On-disk schema

    struct DiskSchema: Codable {
        var hklm: [String: [String: StoredValue]]?
        var hkcu: [String: [String: StoredValue]]?
    }

    struct StoredValue: Codable, Equatable, Hashable, Sendable {
        var type: String
        var value: AnyCodableValue

        init(value: RegistryValue) {
            switch value {
            case .string(let s):
                self.type = "string"
                self.value = .string(s)
            case .dword(let i):
                self.type = "dword"
                self.value = .int(Int64(i))
            case .qword(let i):
                self.type = "qword"
                self.value = .int(i)
            case .binary(let d):
                self.type = "binary"
                self.value = .string(d.base64EncodedString())
            case .multiString(let parts):
                self.type = "multiString"
                self.value = .stringArray(parts)
            }
        }

        func toRegistryValue() -> RegistryValue? {
            switch type {
            case "string":
                if case .string(let s) = value { return .string(s) }
            case "dword":
                if case .int(let v) = value { return .dword(Int32(truncatingIfNeeded: v)) }
            case "qword":
                if case .int(let v) = value { return .qword(v) }
            case "binary":
                if case .string(let s) = value, let data = Data(base64Encoded: s) { return .binary(data) }
            case "multiString":
                if case .stringArray(let parts) = value { return .multiString(parts) }
            default: break
            }
            return nil
        }
    }

    enum AnyCodableValue: Codable, Equatable, Hashable, Sendable {
        case string(String)
        case int(Int64)
        case stringArray([String])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .int(let v): try container.encode(v)
            case .stringArray(let parts): try container.encode(parts)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                self = .string(s); return
            }
            if let v = try? container.decode(Int64.self) {
                self = .int(v); return
            }
            if let parts = try? container.decode([String].self) {
                self = .stringArray(parts); return
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported registry value encoding"
            )
        }
    }
}
