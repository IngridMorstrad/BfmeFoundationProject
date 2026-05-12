import Foundation
import BfmeKit
import BfmeKitCore

/// Foundation port of `ConfigUtils.cs`. Paths root at
/// `~/Library/Application Support/BFME Workshop/` on macOS (or the
/// RegistryStore test override) instead of `%APPDATA%\BFME Workshop` on
/// Windows. The virtual-registry snapshot still uses
/// `BfmeRegistryManager` so workshop scripts that reference HKLM paths see
/// the same state as they would on Windows.
public enum ConfigUtils {
    public static var configDirectory: String {
        BfmeRegistryManager.applicationDataDirectory()
            .appendingPathComponent("BFME Workshop", isDirectory: true)
            .appendingPathComponent("Config", isDirectory: true)
            .path
    }

    public static var libraryDirectory: String {
        BfmeRegistryManager.applicationDataDirectory()
            .appendingPathComponent("BFME Workshop", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .path
    }

    public static let ignoredGameFiles: Set<String> = [
        "_zzlotr.big",
        "cs01.vp6",
        "nlc_logo.vp6",
        "te_logo.vp6",
        "newlinelogo.vp6",
        "ealogo.vp6",
        "242.vp6",
        "intel.vp6",
        "thx.vp6",
        "mod.txt",
        "timer_frame.png"
    ]

    /// Snapshot of the BFME-relevant subset of the registry, keyed by game.
    /// Mirrors the C# `GetVirtualRegistry` helper but uses `BfmeRegistryManager`'s
    /// async surface so reads go through the JSON-backed `RegistryStore`.
    public static func getVirtualRegistry() async -> [Int: BfmeWorkshopEntry.VirtualRegistryEntry] {
        var out: [Int: BfmeWorkshopEntry.VirtualRegistryEntry] = [:]
        for game in 0...2 {
            let rawLanguage = await BfmeRegistryManager.getKeyValue(game, .language)
            let language = BfmeRegistryManager.gameLanguageToLanguageCode(rawLanguage)
            var install = await BfmeRegistryManager.getKeyValue(game, .installPath)
            install = install.trimmingCharacters(in: CharacterSet(charactersIn: "\\/")).lowercased()
            let dataLeaf = await BfmeRegistryManager.getKeyValue(game, .userDataLeafName)
            out[game] = (gameLanguage: language, gameDirectory: install, dataDirectory: dataLeaf)
        }
        return out
    }

    /// Disables an active enhancement and persists the updated dictionary.
    public static func disableEnhancement(
        _ entry: BfmeWorkshopEntry,
        activeEnhancements: inout [String: BfmeWorkshopEntry]
    ) {
        activeEnhancements.removeValue(forKey: entry.guid)
        let filtered = activeEnhancements.filter { $0.value.game == entry.game }
        ensureDirectory(configDirectory)
        FileUtils.writeJSON(
            path: (configDirectory as NSString).appendingPathComponent("active_enhancements_\(entry.game).json"),
            value: filtered
        )
    }

    public static func enableEnhancement(
        _ entry: BfmeWorkshopEntry,
        activeEnhancements: inout [String: BfmeWorkshopEntry]
    ) {
        activeEnhancements[entry.guid] = entry
        let filtered = activeEnhancements.filter { $0.value.game == entry.game }
        ensureDirectory(configDirectory)
        FileUtils.writeJSON(
            path: (configDirectory as NSString).appendingPathComponent("active_enhancements_\(entry.game).json"),
            value: filtered
        )
    }

    /// Persists the active patch JSON for a given game. Mirrors the original
    /// behavior where setting a RotWK patch also cascades a BFME2 base-game
    /// patch record, and setting a BFME2 patch cascades a RotWK one iff
    /// RotWK is installed.
    public static func saveActivePatch(_ patch: BfmeWorkshopEntry) async {
        ensureDirectory(configDirectory)
        FileUtils.writeJSON(
            path: (configDirectory as NSString).appendingPathComponent("active_patch_\(patch.game).json"),
            value: patch
        )
        if patch.game == 2 {
            let bfme2Base = BfmeWorkshopEntry(
                guid: "original-BFME2",
                name: "The Battle for Middle-earth II",
                version: "1.0",
                game: 1,
                type: 0
            )
            FileUtils.writeJSON(
                path: (configDirectory as NSString).appendingPathComponent("active_patch_1.json"),
                value: bfme2Base
            )
        }
        if patch.game == 1 {
            let rotwkInstalled = await BfmeRegistryManager.isInstalled(2)
            if rotwkInstalled {
                let rotwkBase = BfmeWorkshopEntry(
                    guid: "original-RotWK",
                    name: "The Lord of the Rings, The Rise of the Witch-king",
                    version: "1.0",
                    game: 2,
                    type: 0
                )
                FileUtils.writeJSON(
                    path: (configDirectory as NSString).appendingPathComponent("active_patch_2.json"),
                    value: rotwkBase
                )
            }
        }
    }

    /// Writes (or clears) the `mod.txt` file at the install root so the game
    /// and other applications can detect the active mod.
    public static func saveActiveMod(game: Int, modPath: String) async {
        let install = await BfmeRegistryManager.getKeyValue(game, .installPath)
        guard !install.isEmpty else { return }
        let modTxt = (install as NSString).appendingPathComponent("mod.txt")
        if !modPath.isEmpty {
            FileUtils.writeText(path: modTxt, data: modPath)
        } else if FileManager.default.fileExists(atPath: modTxt) {
            try? FileManager.default.removeItem(atPath: modTxt)
        }
    }

    /// Writes the `.syncing` sidecar file that the `FileSystemWatcher` in
    /// the Windows version observes. On macOS we keep the same on-disk
    /// contract so any cross-platform tooling sees identical state.
    public static func saveSyncProgress(game: Int, progress: Int, status: String) {
        ensureDirectory(configDirectory)
        let path = (configDirectory as NSString).appendingPathComponent("active_patch_\(game).syncing")
        if progress >= 0 {
            FileUtils.writeText(path: path, data: "\(progress)\n\(status)")
            if game == 2 {
                let mirrored = (configDirectory as NSString).appendingPathComponent("active_patch_1.syncing")
                FileUtils.writeText(path: mirrored, data: "\(progress)\n\(status)")
            }
        } else {
            for _ in 0..<100 {
                if !FileManager.default.fileExists(atPath: path) { break }
                try? FileManager.default.removeItem(atPath: path)
            }
            if game == 2 {
                let mirrored = (configDirectory as NSString).appendingPathComponent("active_patch_1.syncing")
                for _ in 0..<100 {
                    if !FileManager.default.fileExists(atPath: mirrored) { break }
                    try? FileManager.default.removeItem(atPath: mirrored)
                }
            }
        }
    }

    /// Returns the (progress, status) pair encoded in a sidecar file.
    public static func readSyncProgress(fromFile path: String) -> (progress: Int, status: String) {
        let raw = FileUtils.readText(path: path, default: "0\n")
        let parts = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let progress = Int(parts.first ?? "0") ?? 0
        let status = parts.count > 1 ? parts[1] : ""
        return (progress, status)
    }

    // MARK: - Internals

    static func ensureDirectory(_ path: String) {
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }
}
