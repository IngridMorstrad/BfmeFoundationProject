import Foundation
import BfmeKit

/// Port of `ArenaDataHelper.cs`. Owns the on-disk layout of the arena
/// install. The Windows version roots things under `%APPDATA%`; on macOS
/// we root under `~/Library/Application Support`, which
/// `BfmeRegistryManager.applicationDataDirectory()` already handles.
///
/// The arena executable path keeps the same name the Windows launcher
/// writes (`BfmeFoundationProject_OnlineArena.exe`) so cross-platform
/// tooling that scans for an installed arena on a shared drive still
/// finds it. On a macOS host the file is launched through Wine /
/// CrossOver / Whisky — see `ArenaProcessHelper.launch`.
///
/// `Win32Helper` (see review bullet #13) was intentionally dropped: it
/// was a Windows-only P/Invoke surface (`SetParent`, `MoveWindow`,
/// `SendMessage`) with no portable analog. References in doc comments
/// have been removed.
public enum ArenaDataHelper {
    public static func ensureDirectories() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: globalInstallPath) {
            try? fm.createDirectory(atPath: globalInstallPath, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: globalDataPath) {
            try? fm.createDirectory(atPath: globalDataPath, withIntermediateDirectories: true)
        }
    }

    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: arenaExecutablePath)
    }

    public static var globalInstallPath: String {
        BfmeRegistryManager.applicationDataDirectory()
            .appendingPathComponent("BFME Competetive Arena", isDirectory: true)
            .path
    }

    public static var globalDataPath: String {
        BfmeRegistryManager.applicationDataDirectory()
            .appendingPathComponent("BFME Competetive Arena", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .path
    }

    public static var arenaExecutablePath: String {
        (globalInstallPath as NSString)
            .appendingPathComponent("BfmeFoundationProject_OnlineArena.exe")
    }

    /// Builds the URL the arena menu uses to fetch its latest-version hash.
    /// Kept here so `UpdateHelper` and tests can share one formatter.
    public static func versionHashURL(branch: String) -> String {
        let branchValue = branch.isEmpty ? "~" : branch
        return "\(DeploymentConfig.arenaServerHost)/api/applications/versionHash?name=online-arena&version=\(branchValue)"
    }

    public static func binaryURL(branch: String) -> String {
        "\(DeploymentConfig.arenaFilesHost)/application-builds/online-arena-\(branch)"
    }
}
