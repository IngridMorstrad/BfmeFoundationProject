import Foundation

/// Mirror of `BfmeWorkshopEntryMetadata.cs`. Shipped on preview responses.
public struct BfmeWorkshopEntryMetadata: Codable, Equatable, Hashable, Sendable {
    public var downloads: Int
    public var versions: [String]

    public init(downloads: Int = 0, versions: [String] = []) {
        self.downloads = downloads
        self.versions = versions
    }

    enum CodingKeys: String, CodingKey {
        case downloads = "Downloads"
        case versions = "Versions"
    }
}
