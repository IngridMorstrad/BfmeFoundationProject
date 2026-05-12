import Foundation

/// Mirror of `BfmeWorkshopEntryPreview.cs`. The "card" projection used on
/// the Workshop browse page.
public struct BfmeWorkshopEntryPreview: Codable, Equatable, Hashable, Sendable {
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
    public var size: Int64
    public var creationTime: Int64
    public var metadata: BfmeWorkshopEntryMetadata

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
        size: Int64 = 0,
        creationTime: Int64 = 0,
        metadata: BfmeWorkshopEntryMetadata = BfmeWorkshopEntryMetadata()
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
        self.size = size
        self.creationTime = creationTime
        self.metadata = metadata
    }

    public func gameName() -> String {
        if game == -1 { return "Unknown" }
        return game == 2 ? "RotWK" : "BFME\(game + 1)"
    }

    public func fullName() -> String {
        version.isEmpty ? name : "\(name) (\(version))"
    }

    public func withEmptyMetadata() -> BfmeWorkshopEntryPreview {
        var copy = self
        copy.metadata = BfmeWorkshopEntryMetadata()
        return copy
    }

    public func header() -> BfmeWorkshopEntryHeader {
        BfmeWorkshopEntryHeader(guid: guid, name: name)
    }

    public func workshopEntry() -> BfmeWorkshopEntry {
        BfmeWorkshopEntry(
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
            creationTime: creationTime,
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
        case size = "Size"
        case creationTime = "CreationTime"
        case metadata = "Metadata"
    }
}
