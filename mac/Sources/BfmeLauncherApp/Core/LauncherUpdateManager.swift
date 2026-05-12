import Foundation
import BfmeHttpInstruments

/// macOS rewrite of `LauncherUpdateManager.cs`. The Windows version side-loaded
/// a replacement `AllInOneLauncher_new.exe` and relaunched with `runas`.
/// On macOS the preferred auto-update mechanism is Sparkle (or just App Store
/// distribution); for this phase we only expose the version-hash check
/// against the Arena backend so settings can flag an update as available.
public enum LauncherUpdateManager {
    /// `~/Library/Application Support/BFME All In One Launcher` — the macOS
    /// analogue of `Environment.SpecialFolder.ApplicationData` + the Windows
    /// launcher's leaf directory.
    public static var launcherAppDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("BFME All In One Launcher", isDirectory: true)
    }

    public static func ensureAppDirectoryExists() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: launcherAppDirectory.path) {
            try fm.createDirectory(at: launcherAppDirectory, withIntermediateDirectories: true)
        }
    }

    /// Fetches the latest version hash. Returns `nil` if the probe fails so
    /// the caller can treat a network error as "no update available" rather
    /// than a hard error, matching the C# try/catch flow.
    public static func fetchLatestVersionHash() async -> String? {
        do {
            try ensureAppDirectoryExists()
            let payload = try await HttpMarshal.getString(url: Consts.latestVersionSourceURL)
            return payload.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
