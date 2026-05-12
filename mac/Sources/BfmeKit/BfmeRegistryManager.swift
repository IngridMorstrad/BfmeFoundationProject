import Foundation
import BfmeKitCore

/// 1:1 port of `src/BfmeFoundationProject_BfmeKit/Logic/BfmeRegistryManager.cs`
/// backed by `RegistryStore` instead of the Win32 registry API. Every
/// method is an `async` wrapper around the underlying actor because the store
/// serializes concurrent access. Call sites that previously ran synchronously
/// on Windows just `await` these on macOS.
public enum BfmeRegistryManager {
    // MARK: - Test hooks

    /// Overrides the Application Support base directory (the moral equivalent
    /// of `%APPDATA%` on Windows). Tests set this to point at a temp folder
    /// so Options.ini files land in a sandbox.
    public static var applicationSupportOverride: URL? {
        get { RegistryStore.applicationSupportOverride }
        set {
            RegistryStore.applicationSupportOverride = newValue
            _applicationDataOverride = newValue
        }
    }

    /// Separate knob for the `ApplicationData` root used by `BfmeSettingsManager`
    /// and `EnsureDefaults`. Defaults to the same value as
    /// `applicationSupportOverride` but can be set directly.
    public static var applicationDataOverride: URL? {
        get { _applicationDataOverride }
        set { _applicationDataOverride = newValue }
    }

    private static var _applicationDataOverride: URL?

    // MARK: - Path helpers

    /// Returns the directory that stands in for `Environment.SpecialFolder.ApplicationData`
    /// on macOS: `~/Library/Application Support` (or the override).
    public static func applicationDataDirectory(fileManager: FileManager = .default) -> URL {
        if let override = _applicationDataOverride {
            return override
        }
        let home = fileManager.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    /// Full `SOFTWARE\...` registry path for a given game id. The WOW6432Node
    /// segment is preserved so workshop scripts that reference the literal
    /// Windows path continue to match.
    public static func softwarePath(forGame game: Int, suffix: String = "") -> String {
        let root = BfmeDefaults.defaultGameRegistryKeys[game] ?? ""
        return #"SOFTWARE\WOW6432Node\"# + root + suffix
    }

    static func deprecatedSoftwarePath(forGame game: Int) -> String {
        let root = BfmeDefaults.deprecatedGameRegistryKeys[game] ?? ""
        return #"SOFTWARE\WOW6432Node\"# + root
    }

    // MARK: - Public API mirroring the C# surface

    /// Reads a value from the BFME registry tree. Matches `GetKeyValue` in the
    /// C# original: on `InstallPath`, probes the deprecated path first and
    /// falls through to the canonical one.
    public static func getKeyValue(_ game: Int, _ key: BfmeRegistryKey) async -> String {
        let valueName = registryValueName(for: key)
        let suffix = registrySubkeySuffix(for: key)

        await ensureFixedRegistry(game)

        if key == .installPath {
            let deprecated = deprecatedSoftwarePath(forGame: game)
            if let legacy = await RegistryStore.shared.getValue(hive: .hklm, path: deprecated, name: "Install Dir"),
               case .string(let s) = legacy,
               !s.isEmpty {
                return s
            }
        }

        let path = softwarePath(forGame: game, suffix: suffix)
        guard let stored = await RegistryStore.shared.getValue(hive: .hklm, path: path, name: valueName) else {
            return ""
        }
        return stored.stringValue
    }

    /// Writes a value into the BFME registry tree. Matches `SetKeyValue`.
    public static func setKeyValue(
        _ game: Int,
        _ key: BfmeRegistryKey,
        _ value: String,
        valueType: RegistryValueKind = .string
    ) async throws {
        let valueName = registryValueName(for: key)
        let suffix = registrySubkeySuffix(for: key)
        let path = softwarePath(forGame: game, suffix: suffix)

        if key == .serialKey {
            // The Windows path writes the serial key as the default value (empty name).
            try await RegistryStore.shared.setValue(hive: .hklm, path: path, name: "", value: .string(value))
            return
        }

        let registryValue: RegistryValue
        switch valueType {
        case .string, .multiString:
            registryValue = .string(value)
        case .dword:
            let int32 = Int32(value) ?? 0
            registryValue = .dword(int32)
        case .qword:
            let int64 = Int64(value) ?? 0
            registryValue = .qword(int64)
        case .binary:
            let bytes = Data(base64Encoded: value) ?? Data(value.utf8)
            registryValue = .binary(bytes)
        }

        try await RegistryStore.shared.setValue(hive: .hklm, path: path, name: valueName, value: registryValue)
    }

    /// Writes the canonical set of values a fresh install would produce.
    public static func createNewInstallRegistry(_ game: Int, installPath: String, language: String) async throws {
        var normalizedInstallPath = installPath
        if !normalizedInstallPath.hasSuffix("/") && !normalizedInstallPath.hasSuffix(#"\"#) {
            normalizedInstallPath += "/"
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: normalizedInstallPath) {
            try fm.createDirectory(
                at: URL(fileURLWithPath: normalizedInstallPath),
                withIntermediateDirectories: true
            )
        }

        await ensureFixedRegistry(game)
        try await setKeyValue(game, .installPath, normalizedInstallPath)
        try await setKeyValue(game, .language, language)
        try await setKeyValue(game, .mapPackVersion, "65536", valueType: .dword)
        try await setKeyValue(game, .useLocalUserMaps, "0", valueType: .dword)
        try await setKeyValue(game, .userDataLeafName, BfmeDefaults.defaultUserDataLeafNames[game] ?? "")
        try await setKeyValue(game, .version, "65539", valueType: .dword)
        try await setKeyValue(game, .serialKey, generateFakeSerialKey())
        try await ensureDefaults(game)
    }

    /// Emits the set of compatibility subkeys the C# version installs under
    /// `SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\...` and makes sure
    /// the user-data leaf exists with an `Options.ini`.
    public static func ensureDefaults(_ game: Int) async throws {
        let executable = BfmeDefaults.defaultGameExecutableNames[game] ?? ""
        let appPathsKey = #"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\"# + executable
        try? await RegistryStore.shared.deleteSubKeyTree(hive: .hklm, path: appPathsKey)
        try await RegistryStore.shared.createSubKey(hive: .hklm, path: appPathsKey)

        let installPath = await getKeyValue(game, .installPath)
        let gameRegistryRoot = #"SOFTWARE\"# + (BfmeDefaults.defaultGameRegistryKeys[game] ?? "")

        try await RegistryStore.shared.setValue(
            hive: .hklm, path: appPathsKey, name: "",
            value: .string(joinPath(installPath, executable))
        )
        try await RegistryStore.shared.setValue(
            hive: .hklm, path: appPathsKey, name: "Game Registry",
            value: .string(gameRegistryRoot)
        )
        try await RegistryStore.shared.setValue(
            hive: .hklm, path: appPathsKey, name: "Installed",
            value: .dword(1)
        )
        try await RegistryStore.shared.setValue(
            hive: .hklm, path: appPathsKey, name: "Path",
            value: .string(installPath)
        )
        try await RegistryStore.shared.setValue(
            hive: .hklm, path: appPathsKey, name: "Restart",
            value: .dword(0)
        )

        // User data directory + Options.ini.
        let fm = FileManager.default
        let userDataLeaf = await getKeyValue(game, .userDataLeafName)
        if !userDataLeaf.isEmpty {
            let userDataURL = applicationDataDirectory(fileManager: fm)
                .appendingPathComponent(userDataLeaf, isDirectory: true)
            if !fm.fileExists(atPath: userDataURL.path) {
                try? fm.createDirectory(at: userDataURL, withIntermediateDirectories: true)
            }
            let optionsURL = userDataURL.appendingPathComponent("Options.ini")
            let existing = try? String(contentsOf: optionsURL, encoding: .utf8)
            let shouldRewrite = existing == nil
                || (existing?.count ?? 0) <= 6
                || !(existing?.contains("Resolution = ") ?? false)
            if shouldRewrite {
                try? BfmeDefaults.defaultOptions.write(to: optionsURL, atomically: true, encoding: .utf8)
            }
        }

        // The C# version also re-asserts the fixed registry for the .exe and
        // game.dat paths (used as registry keys by Wine/Win32 shim layers).
        // These are harmless no-ops on macOS since the deprecated key tree
        // doesn't exist; we just register the subkey so workshop scripts can
        // probe it.
        let exePath = joinPath(installPath, executable)
        let datPath = joinPath(installPath, "game.dat")
        try? await RegistryStore.shared.createSubKey(hive: .hklm, path: #"SOFTWARE\WOW6432Node\Executables\"# + exePath)
        try? await RegistryStore.shared.createSubKey(hive: .hklm, path: #"SOFTWARE\WOW6432Node\Executables\"# + datPath)

        // `EnsureCompatibilitySettings` is a Windows-only shim (AppCompatFlags
        // layers). The macOS build logs and skips.
        ensureCompatibilitySettings(exePath)
        ensureCompatibilitySettings(datPath)

        if game == 2 {
            // ROTWK quietly ensures BFME2 defaults too.
            try await ensureDefaults(1)
        }
    }

    /// The C# version copied the legacy `Install Dir` string from
    /// `HKLM\SOFTWARE\EA GAMES\...` into the canonical key, guarded by an
    /// Administrator check (required on Windows for HKLM writes). On macOS
    /// there is no elevation layer — every user owns their own registry
    /// file — so the call drops the principal check and just runs.
    public static func ensureFixedRegistry(_ game: Int) async {
        let deprecated = deprecatedSoftwarePath(forGame: game)
        guard let legacy = await RegistryStore.shared.getValue(hive: .hklm, path: deprecated, name: "Install Dir"),
              case .string(let installDir) = legacy,
              !installDir.isEmpty else {
            return
        }
        try? await setKeyValue(game, .installPath, installDir)
        try? await RegistryStore.shared.deleteSubKeyTree(hive: .hklm, path: deprecated)
    }

    /// No-op on macOS: the original body wrote to
    /// `HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers`
    /// to force Windows XP SP3 compatibility mode. macOS has no equivalent
    /// shim layer. We keep the entry point so the call sites in
    /// `EnsureDefaults` don't need to branch, and we emit a single log line
    /// per call so the behavior matches what the doc comment promises
    /// (review bullet #10).
    public static func ensureCompatibilitySettings(_ gamePath: String) {
        print("BfmeRegistryManager.ensureCompatibilitySettings: skipping AppCompatFlags write on non-Windows host for \(gamePath).")
    }

    /// Reports whether a game's `InstallPath` points at a directory that
    /// currently exists on disk.
    public static func isInstalled(_ game: Int) async -> Bool {
        let path = await getKeyValue(game, .installPath)
        guard !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public static func gameNameToInt(_ gameName: String) -> Int {
        switch gameName.uppercased() {
        case "BFME1": return 0
        case "BFME2": return 1
        case "ROTWK": return 2
        default: return 0
        }
    }

    public static func gameLanguageToLanguageCode(_ language: String) -> String {
        let map: [String: String] = [
            "english": "EN",
            "english uk": "EN",
            "english us": "EN",
            "french": "FR",
            "german": "DE",
            "italian": "IT",
            "spanish": "ES",
            "swedish": "SV",
            "dutch": "NL",
            "polish": "PL",
            "norwegian": "NO",
            "russian": "RU",
            "turkish": "TR"
        ]
        let key = language.lowercased()
        if let code = map[key] { return code }
        return key
    }

    public static func gameLanguageCodeToLanguage(_ code: String) -> String {
        let map: [String: String] = [
            "en": "English",
            "fr": "French",
            "de": "German",
            "it": "Italian",
            "es": "Spanish",
            "sv": "Swedish",
            "nl": "Dutch",
            "pl": "Polish",
            "no": "Norwegian",
            "ru": "Russian",
            "tr": "Turkish"
        ]
        let key = code.lowercased()
        if let language = map[key] { return language }
        return key
    }

    // MARK: - Internal helpers

    private static func registryValueName(for key: BfmeRegistryKey) -> String {
        switch key {
        case .installPath: return "InstallPath"
        case .language: return "Language"
        case .mapPackVersion: return "MapPackVersion"
        case .useLocalUserMaps: return "UseLocalUserMaps"
        case .userDataLeafName: return "UserDataLeafName"
        case .version: return "Version"
        case .serialKey: return ""
        }
    }

    private static func registrySubkeySuffix(for key: BfmeRegistryKey) -> String {
        switch key {
        case .serialKey: return #"\ergc"#
        default: return ""
        }
    }

    private static func joinPath(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if a.hasSuffix("/") || a.hasSuffix(#"\"#) { return a + b }
        return a + "/" + b
    }

    private static func generateFakeSerialKey() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var out = ""
        out.reserveCapacity(20)
        for _ in 0..<20 {
            out.append(alphabet.randomElement()!)
        }
        return out
    }
}
