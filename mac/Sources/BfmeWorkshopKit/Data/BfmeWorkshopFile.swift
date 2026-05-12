import Foundation

/// Single downloadable file bundled in a workshop entry. 1:1 mirror of
/// `src/BfmeFoundationProject_WorkshopKit/Data/BfmeWorkshopFile.cs`.
///
/// The Windows launcher ships uses Newtonsoft.Json with default member-name
/// casing, so the JSON wire format on `workshop-files.bfmeladder.com` is
/// PascalCase. The `CodingKeys` block below pins that contract so a Swift
/// client stays byte-compatible with the .NET one.
public struct BfmeWorkshopFile: Codable, Equatable, Hashable, Sendable {
    public var guid: String
    public var name: String
    public var url: String
    public var md5: String
    public var language: String
    public var size: Int64

    public init(
        guid: String = "",
        name: String = "",
        url: String = "",
        md5: String = "",
        language: String = "",
        size: Int64 = 0
    ) {
        self.guid = guid
        self.name = name
        self.url = url
        self.md5 = md5
        self.language = language
        self.size = size
    }

    enum CodingKeys: String, CodingKey {
        case guid = "Guid"
        case name = "Name"
        case url = "Url"
        case md5 = "Md5"
        case language = "Language"
        case size = "Size"
    }
}
