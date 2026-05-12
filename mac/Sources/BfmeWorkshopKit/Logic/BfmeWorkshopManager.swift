import Foundation
import BfmeKit
import BfmeKitCore

/// Top-level facade for the Workshop subsystem. Holds the shared host
/// constants and the lightweight per-game state-read helpers. Mirrors the
/// surface of `BfmeWorkshopManager.cs`.
public enum BfmeWorkshopManager {
    /// The backend that fronts the workshop database + auth.
    public static let workshopServerHost = "https://bfmeladder.com"
    /// The workshop file store (Cloudflare R2 behind a CDN).
    public static let workshopFilesHost = "https://workshop-files.bfmeladder.com"

    public static func getActivePatch(_ game: Int) async -> BfmeWorkshopEntry? {
        let path = (ConfigUtils.configDirectory as NSString)
            .appendingPathComponent("active_patch_\(game).json")
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let placeholder = BfmeWorkshopEntry()
        let result: BfmeWorkshopEntry = FileUtils.readJSON(path: path, default: placeholder)
        if result.guid.isEmpty { return nil }
        return result
    }

    public static func getActiveEnhancements(_ game: Int) async -> [String: BfmeWorkshopEntry] {
        let path = (ConfigUtils.configDirectory as NSString)
            .appendingPathComponent("active_enhancements_\(game).json")
        return FileUtils.readJSON(path: path, default: [:])
    }

    public static func getActiveModPath(_ game: Int) async -> String {
        let install = await BfmeRegistryManager.getKeyValue(game, .installPath)
        guard !install.isEmpty else { return "" }
        let modTxt = (install as NSString).appendingPathComponent("mod.txt")
        return FileUtils.readText(path: modTxt, default: "")
    }

    public static func isPatchActive(_ game: Int, entryGuid: String) async -> Bool {
        let path = (ConfigUtils.configDirectory as NSString)
            .appendingPathComponent("active_patch_\(game).json")
        return FileUtils.contains(path: path, text: "\"Guid\" : \"\(entryGuid)\"")
            || FileUtils.contains(path: path, text: "\"Guid\": \"\(entryGuid)\"")
    }

    public static func isEnhancementActive(_ game: Int, entryGuid: String) async -> Bool {
        let path = (ConfigUtils.configDirectory as NSString)
            .appendingPathComponent("active_enhancements_\(game).json")
        return FileUtils.contains(path: path, text: "\"Guid\" : \"\(entryGuid)\"")
            || FileUtils.contains(path: path, text: "\"Guid\": \"\(entryGuid)\"")
    }
}
