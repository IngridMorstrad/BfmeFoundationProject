import Foundation

/// Small portable helper that loads/saves a user-preferences dictionary under
/// `~/Library/Application Support/BFME Foundation/launcher-settings.json`.
/// Replaces `Properties.Settings.Default` in the C# source — the
/// ApplicationSettings framework is Windows-only. We keep the same keys the
/// C# code used so Workshop scripts and persisted user prefs round-trip.
public enum LauncherStateManager {
    /// Override used by tests to point at a temp directory.
    nonisolated(unsafe) public static var storageOverride: URL?

    public static var storageURL: URL {
        if let override = storageOverride {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("BFME Foundation", isDirectory: true)
            .appendingPathComponent("launcher-settings.json")
    }

    public static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: storageURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return obj
    }

    public static func save(_ dict: [String: String]) throws {
        let url = storageURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.sortedKeys, .prettyPrinted]
        )
        try data.write(to: url, options: .atomic)
    }

    public static func value(for key: String, default fallback: String = "") -> String {
        load()[key] ?? fallback
    }

    public static func setValue(_ value: String, for key: String) throws {
        var dict = load()
        dict[key] = value
        try save(dict)
    }

    // Well-known keys from the original `Properties.Settings`.
    public static let launcherLanguageKey = "LauncherLanguage"
    public static let hideToTrayOnCloseKey = "HideToTrayOnClose"
    public static let arenaUpdateBranchKey = "ArenaUpdateBranch"
}
