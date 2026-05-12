import Foundation

/// Mirror of `BfmeWorkshopEntryHeader.cs`. Minimal header record returned
/// alongside query results and used by the download manager to reference
/// other entries.
public struct BfmeWorkshopEntryHeader: Codable, Equatable, Hashable, Sendable {
    public var guid: String
    public var name: String

    public init(guid: String = "", name: String = "") {
        self.guid = guid
        self.name = name
    }

    /// Matches the `WorkshopEntry()` convenience on the C# struct: inflates
    /// this header into a full, empty entry.
    public func workshopEntry() -> BfmeWorkshopEntry {
        BfmeWorkshopEntry(
            guid: guid,
            name: name,
            version: "",
            description: "",
            changelog: "",
            socialLinks: [],
            language: "",
            artworkUrl: "",
            screenshotUrls: [],
            author: "",
            owner: "",
            game: 0,
            type: 0,
            creationTime: 0,
            files: [],
            maps: [],
            factions: [],
            dependencies: []
        )
    }

    enum CodingKeys: String, CodingKey {
        case guid = "Guid"
        case name = "Name"
    }
}
