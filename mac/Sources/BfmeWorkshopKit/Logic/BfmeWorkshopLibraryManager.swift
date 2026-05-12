import Foundation

/// Port of `BfmeWorkshopLibraryManager.cs`. Tracks the user's "owned" set
/// of workshop entries as JSON files under
/// `~/Library/Application Support/BFME Workshop/Library/`.
public enum BfmeWorkshopLibraryManager {
    /// Filters, paginates and returns the preview projection of the library.
    /// Auto-populates the library with the base games + official patches on
    /// first use, same as the C# version.
    public static func query(
        keyword: String = "",
        game: Int = -1,
        type: Int = -1,
        page: Int = 0
    ) async throws -> [BfmeWorkshopEntryPreview] {
        ensureLibraryBootstrapped()

        let files = (try? FileManager.default.contentsOfDirectory(atPath: ConfigUtils.libraryDirectory)) ?? []
        var entries: [BfmeWorkshopEntryPreview] = []
        for name in files.sorted() where name.hasSuffix(".json") {
            let full = (ConfigUtils.libraryDirectory as NSString).appendingPathComponent(name)
            let entry: BfmeWorkshopEntry = FileUtils.readJSON(path: full, default: BfmeWorkshopEntry())
            if entry.guid.isEmpty { continue }
            entries.append(entry.preview(metadata: BfmeWorkshopEntryMetadata()))
        }

        entries = entries.sorted { lhs, rhs in
            func rank(_ p: BfmeWorkshopEntryPreview) -> Int {
                if p.guid.hasPrefix("exp-original-") { return 0 }
                if p.guid.hasPrefix("original-") { return 1 }
                if p.guid.hasPrefix("official-") { return 2 }
                return 3
            }
            let l = rank(lhs), r = rank(rhs)
            if l != r { return l < r }
            return lhs.name < rhs.name
        }

        if !keyword.isEmpty {
            let needle = keyword.lowercased()
            entries = entries.filter { e in
                e.name.lowercased().contains(needle) || e.description.lowercased().contains(needle)
            }
        }
        if game != -1 {
            entries = entries.filter { $0.game == game }
        }
        if type != -1 {
            if type == -2 { entries = entries.filter { $0.type == 0 || $0.type == 1 } }
            else if type == -3 { entries = entries.filter { $0.type == 2 || $0.type == 3 } }
            else { entries = entries.filter { $0.type == type } }
        }

        if page == -1 { return entries }

        let start = page * 25
        guard start < entries.count else { return [] }
        let end = min(start + 25, entries.count)
        return Array(entries[start..<end]).map { $0.withEmptyMetadata() }
    }

    public static func get(entryGuid: String) throws -> BfmeWorkshopEntry {
        let path = (ConfigUtils.libraryDirectory as NSString)
            .appendingPathComponent("\(entryGuid).json")
        guard FileManager.default.fileExists(atPath: path) else {
            throw BfmeWorkshopError.entryNotFound(
                "The package with guid \(entryGuid) was not found in the library!"
            )
        }
        return FileUtils.readJSON(path: path, default: BfmeWorkshopEntry())
    }

    public static func addOrUpdate(_ entry: BfmeWorkshopEntry) {
        ConfigUtils.ensureDirectory(ConfigUtils.libraryDirectory)
        let path = (ConfigUtils.libraryDirectory as NSString)
            .appendingPathComponent("\(entry.guid).json")
        FileUtils.writeJSON(path: path, value: entry)
    }

    public static func remove(entryGuid: String) {
        let path = (ConfigUtils.libraryDirectory as NSString)
            .appendingPathComponent("\(entryGuid).json")
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    public static func isInLibrary(entryGuid: String) -> Bool {
        let path = (ConfigUtils.libraryDirectory as NSString)
            .appendingPathComponent("\(entryGuid).json")
        return FileManager.default.fileExists(atPath: path)
    }

    // MARK: - Bootstrap

    static func ensureLibraryBootstrapped() {
        ConfigUtils.ensureDirectory(ConfigUtils.configDirectory)
        ConfigUtils.ensureDirectory(ConfigUtils.libraryDirectory)

        let flagPath = (ConfigUtils.configDirectory as NSString)
            .appendingPathComponent("library_version.flag")
        let current = FileUtils.readText(path: flagPath, default: "")
        if current != "2" {
            if FileManager.default.fileExists(atPath: ConfigUtils.libraryDirectory) {
                try? FileManager.default.removeItem(atPath: ConfigUtils.libraryDirectory)
            }
            ConfigUtils.ensureDirectory(ConfigUtils.libraryDirectory)
            FileUtils.writeText(path: flagPath, data: "2")
        }
    }
}
