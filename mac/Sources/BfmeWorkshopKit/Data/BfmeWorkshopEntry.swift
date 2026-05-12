import Foundation
import BfmeKitCore

/// 1:1 port of `BfmeWorkshopEntry.cs`. The wire format on the
/// `bfmeladder.com` Workshop backend is the default Newtonsoft.Json
/// serialization (PascalCase, no kebab/snake), so this struct opts in via
/// explicit PascalCase `CodingKeys` rather than relying on a global key
/// strategy.
public struct BfmeWorkshopEntry: Codable, Equatable, Hashable, Sendable {
    public var guid: String
    public var name: String
    public var version: String
    public var description: String
    public var changelog: String
    public var socialLinks: [String]
    public var language: String
    public var artworkUrl: String
    public var screenshotUrls: [String]
    public var author: String
    public var owner: String
    public var game: Int
    public var type: Int
    public var creationTime: Int64
    public var files: [BfmeWorkshopFile]
    public var maps: [BfmeMap]
    public var factions: [BfmeFaction]
    public var dependencies: [String]

    public init(
        guid: String = "",
        name: String = "",
        version: String = "",
        description: String = "",
        changelog: String = "",
        socialLinks: [String] = [],
        language: String = "",
        artworkUrl: String = "",
        screenshotUrls: [String] = [],
        author: String = "",
        owner: String = "",
        game: Int = 0,
        type: Int = 0,
        creationTime: Int64 = 0,
        files: [BfmeWorkshopFile] = [],
        maps: [BfmeMap] = [],
        factions: [BfmeFaction] = [],
        dependencies: [String] = []
    ) {
        self.guid = guid
        self.name = name
        self.version = version
        self.description = description
        self.changelog = changelog
        self.socialLinks = socialLinks
        self.language = language
        self.artworkUrl = artworkUrl
        self.screenshotUrls = screenshotUrls
        self.author = author
        self.owner = owner
        self.game = game
        self.type = type
        self.creationTime = creationTime
        self.files = files
        self.maps = maps
        self.factions = factions
        self.dependencies = dependencies
    }

    public func isBaseGame() -> Bool {
        guid.hasPrefix("original-") || guid.hasPrefix("exp-original-")
    }

    public func gameName() -> String {
        game == 2 ? "RotWK" : "BFME\(game + 1)"
    }

    public func fullName() -> String {
        "\(name) (\(version))"
    }

    public func packageSize() -> Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    public func header(includeVersion: Bool = false) -> BfmeWorkshopEntryHeader {
        BfmeWorkshopEntryHeader(
            guid: includeVersion ? "\(guid):\(version)" : guid,
            name: name
        )
    }

    public func preview(metadata: BfmeWorkshopEntryMetadata) -> BfmeWorkshopEntryPreview {
        BfmeWorkshopEntryPreview(
            guid: guid,
            name: name,
            version: version,
            description: description,
            changelog: changelog,
            socialLinks: socialLinks,
            language: language,
            artworkUrl: artworkUrl,
            screenshotUrls: screenshotUrls,
            author: author,
            owner: owner,
            game: game,
            type: type,
            size: packageSize(),
            creationTime: creationTime,
            metadata: metadata
        )
    }

    public func withCreationTimeSetToNow() -> BfmeWorkshopEntry {
        var copy = self
        copy.creationTime = Int64(Date().timeIntervalSince1970 * 1000)
        return copy
    }

    public func withThisAsBaseInfo(_ source: BfmeWorkshopEntry, inheritVersion: Bool = false, inheritAuthor: Bool = false) -> BfmeWorkshopEntry {
        var copy = self
        copy.guid = source.guid
        copy.name = source.name
        copy.owner = source.owner
        copy.type = source.type
        if inheritVersion { copy.version = source.version }
        if inheritAuthor { copy.author = source.author }
        return copy
    }

    public func withoutFiles() -> BfmeWorkshopEntry {
        var copy = self
        copy.files = []
        return copy
    }

    public func withVersionBumped() -> BfmeWorkshopEntry {
        var copy = self
        let parts = version.split(separator: ".").map(String.init)
        guard let last = parts.last else { return copy }
        let head = parts.dropLast()
        let bumped: String
        if let asInt = Int(last) {
            bumped = String(asInt + 1)
        } else {
            bumped = last
        }
        copy.version = (head + [bumped]).joined(separator: ".")
        return copy
    }

    /// Returns a uniformly random map from `maps`, optionally weighted by a
    /// `[mapId: weight]` table. Mirrors the logic of `BfmeWorkshopEntry.GetRandomMap`.
    public func getRandomMap(weights: [String: Int]? = nil) -> BfmeMap? {
        guard !maps.isEmpty else { return nil }

        if let weights = weights {
            let pool = maps.filter { weights[$0.id] != nil }
            guard !pool.isEmpty else { return nil }
            let poolSize = weights.values.reduce(0, +)
            let randomNumber = Int.random(in: 0..<max(poolSize, 1)) + 1
            var accumulated = 0
            for map in pool {
                accumulated += weights[map.id] ?? 0
                if randomNumber <= accumulated { return map }
            }
            return pool.first
        }
        return maps.randomElement()
    }

    /// A virtual registry row as produced by `ConfigUtils.getVirtualRegistry()`.
    public typealias VirtualRegistryEntry = (gameLanguage: String, gameDirectory: String, dataDirectory: String)

    /// Resolves the directory the files of this entry should be written into
    /// based on `Type`. Mirrors `BfmeWorkshopEntry.GetDestinationDirectory`.
    public func getDestinationDirectory(
        virtualRegistry: [Int: VirtualRegistryEntry],
        applicationData: URL
    ) -> String {
        let gameDir = virtualRegistry[game]?.gameDirectory ?? ""
        let dataDir = virtualRegistry[game]?.dataDirectory ?? ""

        switch type {
        case 0, 2, 4:
            return gameDir
        case 1:
            // Mods live parallel to the install folder under BFME Workshop/Mods.
            let separators: Set<Character> = ["\\", "/"]
            let parts = gameDir.split(whereSeparator: { separators.contains($0) }).map(String.init).dropLast()
            let parent = parts.joined(separator: "\\")
            let safeName = String(name.map { BfmeWorkshopEntry.invalidPathChars.contains($0) ? "_" : $0 })
            return parent + "\\BFME Workshop\\Mods\\" + "\(safeName)-\(guid)"
        case 3:
            return applicationData.appendingPathComponent(dataDir, isDirectory: true)
                .appendingPathComponent("Maps", isDirectory: true)
                .appendingPathComponent("Workshop", isDirectory: true)
                .path
        default:
            return gameDir
        }
    }

    /// A conservative superset of the characters that are invalid on any
    /// platform the launcher targets. Matches `Path.GetInvalidPathChars()`
    /// from the .NET Framework on Windows plus the POSIX-specific `/`.
    static let invalidPathChars: Set<Character> = [
        "\u{0}", "\t", "\n", "\r", "\u{0B}", "\u{0C}",
        "<", ">", ":", "\"", "|", "?", "*"
    ]

    public static func makeNew(game: Int = 0, author: String = "", owner: String = "") -> BfmeWorkshopEntry {
        BfmeWorkshopEntry(
            guid: UUID().uuidString.lowercased(),
            name: "",
            version: "1.0.0",
            description: "",
            changelog: "",
            socialLinks: [],
            language: "",
            artworkUrl: "",
            screenshotUrls: [],
            author: author,
            owner: owner,
            game: game,
            type: 0,
            creationTime: Int64(Date().timeIntervalSince1970 * 1000),
            files: [],
            maps: [],
            factions: [],
            dependencies: []
        )
    }

    enum CodingKeys: String, CodingKey {
        case guid = "Guid"
        case name = "Name"
        case version = "Version"
        case description = "Description"
        case changelog = "Changelog"
        case socialLinks = "SocialLinks"
        case language = "Language"
        case artworkUrl = "ArtworkUrl"
        case screenshotUrls = "ScreenshotUrls"
        case author = "Author"
        case owner = "Owner"
        case game = "Game"
        case type = "Type"
        case creationTime = "CreationTime"
        case files = "Files"
        case maps = "Maps"
        case factions = "Factions"
        case dependencies = "Dependencies"
    }
}
