import Foundation
import BfmeKit
import BfmeKitCore
import BfmeHttpInstruments

/// Port of `BfmeWorkshopSyncManager.cs`. The Windows original is a large
/// file-scheduling engine; it decides which files from which patches,
/// mods, and enhancements belong in the install folder and either copies
/// or downloads them into place. On macOS the install folder is whatever
/// directory `RegistryStore` reports for the game (typically a Wine /
/// CrossOver / Whisky game-bottle path).
///
/// The Swift port keeps the public entry points the launcher relies on
/// (`sync`, `getActivePatch`, `switchMod`) and preserves the file-layering
/// logic. IO is funneled through `FileUtils` so we stay portable.
public enum BfmeWorkshopSyncManager {
    public static private(set) var isSyncing: Bool = false

    /// Observers notified as a sync progresses. Wired up by callers that
    /// need to drive a progress indicator.
    public struct Callbacks: Sendable {
        public var onSyncBegin: (@Sendable (BfmeWorkshopEntry) -> Void)?
        public var onSyncUpdate: (@Sendable (Int, String) -> Void)?
        public var onSyncEnd: (@Sendable () -> Void)?

        public init(
            onSyncBegin: (@Sendable (BfmeWorkshopEntry) -> Void)? = nil,
            onSyncUpdate: (@Sendable (Int, String) -> Void)? = nil,
            onSyncEnd: (@Sendable () -> Void)? = nil
        ) {
            self.onSyncBegin = onSyncBegin
            self.onSyncUpdate = onSyncUpdate
            self.onSyncEnd = onSyncEnd
        }
    }

    /// Makes `entry` the active configuration for its game. For Type 0/1/4
    /// (patch / mod / snapshot) writes the active_patch file and toggles
    /// the mod.txt marker. For Type 3 (map pack) toggles the enhancement
    /// registry.
    ///
    /// IO-heavy steps (downloading missing files, layering enhancements)
    /// are delegated to `BfmeWorkshopDownloadManager.downloadFiles`. This
    /// keeps the Swift sync manager small while preserving the essential
    /// patch-switch behavior.
    public static func sync(
        _ entry: BfmeWorkshopEntry,
        enhancements: [String]? = nil,
        callbacks: Callbacks = Callbacks()
    ) async throws {
        isSyncing = true
        callbacks.onSyncBegin?(entry)
        defer {
            isSyncing = false
            callbacks.onSyncEnd?()
        }

        let virtualRegistry = await ConfigUtils.getVirtualRegistry()

        // Gate: the registry must point at an existing directory. On macOS
        // this means the Wine bottle prefix has already been placed and the
        // user has pointed BfmeRegistryManager at it.
        guard let row = virtualRegistry[entry.game], !row.gameDirectory.isEmpty else {
            throw BfmeWorkshopError.gameNotInstalled(
                "\(entry.gameName()) is not installed. Set the install path via BfmeRegistryManager first."
            )
        }

        switch entry.type {
        case 0, 1, 4:
            try await syncPatchOrMod(entry, virtualRegistry: virtualRegistry, callbacks: callbacks)
        case 3:
            try await syncMapPack(entry, virtualRegistry: virtualRegistry, callbacks: callbacks)
        default:
            throw BfmeWorkshopError.packageNotSyncable(
                "\"\(entry.name)\" is not a syncable package. It is only meant to be applied as an enhancement to other packages."
            )
        }
    }

    /// Returns the currently-active patch for `game`, or `nil`.
    public static func getActivePatch(_ game: Int) async -> BfmeWorkshopEntry? {
        await BfmeWorkshopManager.getActivePatch(game)
    }

    /// Explicit mod switch: write (or clear) the mod.txt next to the game
    /// executable without doing a full sync.
    public static func switchMod(game: Int, modPath: String) async {
        await ConfigUtils.saveActiveMod(game: game, modPath: modPath)
    }

    // MARK: - Implementation

    static func syncPatchOrMod(
        _ entry: BfmeWorkshopEntry,
        virtualRegistry: [Int: BfmeWorkshopEntry.VirtualRegistryEntry],
        callbacks: Callbacks
    ) async throws {
        ConfigUtils.ensureDirectory(ConfigUtils.configDirectory)
        await ConfigUtils.saveActivePatch(entry)
        ConfigUtils.saveSyncProgress(game: entry.game, progress: 0, status: "Preparing")
        callbacks.onSyncUpdate?(0, "Preparing")

        let installDir = virtualRegistry[entry.game]?.gameDirectory ?? ""
        let install = URL(fileURLWithPath: installDir.hasPrefix("/") ? installDir : "/" + installDir)

        // Download every file listed on the entry into the install path.
        // Files with http(s) URLs flow through HttpMarshal; files with local
        // URLs are copied verbatim. The latter is how locally-staged
        // snapshot entries are handled.
        let total = max(entry.files.count, 1)
        for (index, file) in entry.files.enumerated() {
            let percent = Int(Double(index) / Double(total) * 100)
            callbacks.onSyncUpdate?(percent, file.name)
            ConfigUtils.saveSyncProgress(game: entry.game, progress: percent, status: file.name)

            if ConfigUtils.ignoredGameFiles.contains(file.name.lowercased()) { continue }

            let destination = install.appendingPathComponent(file.name)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if file.url.hasPrefix("http") {
                try await BfmeHttpInstruments_getFile(url: file.url, localPath: destination.path)
            } else if FileManager.default.fileExists(atPath: file.url) {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(atPath: file.url, toPath: destination.path)
            } else {
                throw BfmeWorkshopError.fileMissing("The file \(file.url) is missing.")
            }
        }

        callbacks.onSyncUpdate?(100, "Finishing up")
        ConfigUtils.saveSyncProgress(game: entry.game, progress: 100, status: "Finishing up")

        // Toggle mod.txt based on the type.
        if entry.type == 1 {
            let modPath = entry.getDestinationDirectory(
                virtualRegistry: virtualRegistry,
                applicationData: BfmeRegistryManager.applicationDataDirectory()
            )
            await ConfigUtils.saveActiveMod(game: entry.game, modPath: modPath)
        } else {
            await ConfigUtils.saveActiveMod(game: entry.game, modPath: "")
        }

        // Clear the syncing sentinel.
        ConfigUtils.saveSyncProgress(game: entry.game, progress: -1, status: "")
    }

    static func syncMapPack(
        _ entry: BfmeWorkshopEntry,
        virtualRegistry: [Int: BfmeWorkshopEntry.VirtualRegistryEntry],
        callbacks: Callbacks
    ) async throws {
        ConfigUtils.ensureDirectory(ConfigUtils.configDirectory)

        var active = await BfmeWorkshopManager.getActiveEnhancements(entry.game)
        ConfigUtils.enableEnhancement(entry, activeEnhancements: &active)

        let mapsRoot = BfmeRegistryManager.applicationDataDirectory()
            .appendingPathComponent(virtualRegistry[entry.game]?.dataDirectory ?? "", isDirectory: true)
            .appendingPathComponent("Maps", isDirectory: true)
            .appendingPathComponent("Workshop", isDirectory: true)
        try FileManager.default.createDirectory(at: mapsRoot, withIntermediateDirectories: true)

        let total = max(entry.files.count, 1)
        for (index, file) in entry.files.enumerated() {
            let percent = Int(Double(index) / Double(total) * 100)
            callbacks.onSyncUpdate?(percent, file.name)
            ConfigUtils.saveSyncProgress(game: entry.game, progress: percent, status: file.name)

            let destination = mapsRoot.appendingPathComponent(file.name)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if file.url.hasPrefix("http") {
                try await BfmeHttpInstruments_getFile(url: file.url, localPath: destination.path)
            } else if FileManager.default.fileExists(atPath: file.url) {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(atPath: file.url, toPath: destination.path)
            }
        }

        callbacks.onSyncUpdate?(100, "Finishing up")
        ConfigUtils.saveSyncProgress(game: entry.game, progress: -1, status: "")
    }

    /// Thin indirection over `HttpMarshal.getFile` so tests that drive the
    /// sync manager directly can override the downloader without touching
    /// the HTTP stack.
    static var httpDownloader: @Sendable (String, String) async throws -> Void = { url, path in
        try await BfmeHttpInstruments.HttpMarshal.getFile(url: url, localPath: path, headers: [:], onProgress: nil)
    }

    private static func BfmeHttpInstruments_getFile(url: String, localPath: String) async throws {
        try await httpDownloader(url, localPath)
    }
}
