import Foundation

public struct BfmeFaction: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var id: Int
    public var bigIcon: String
    public var smallIcon: String

    public init(name: String, id: Int, bigIcon: String, smallIcon: String) {
        self.name = name
        self.id = id
        self.bigIcon = bigIcon
        self.smallIcon = smallIcon
    }

    // JSON wire format on the Workshop backend is PascalCase (Newtonsoft.Json
    // defaults). Pinning the coding keys here keeps the Swift client
    // byte-compatible with the .NET one.
    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
        case bigIcon = "BigIcon"
        case smallIcon = "SmallIcon"
    }

    public static func standardBfme1Factions() -> [BfmeFaction] {
        [
            BfmeFaction(name: "Rohan", id: 3, bigIcon: "STANDARD:rohan.png", smallIcon: "STANDARD:rohan.png"),
            BfmeFaction(name: "Gondor", id: 4, bigIcon: "STANDARD:gondor.png", smallIcon: "STANDARD:gondor.png"),
            BfmeFaction(name: "Isengard", id: 5, bigIcon: "STANDARD:isengard.png", smallIcon: "STANDARD:isengard.png"),
            BfmeFaction(name: "Mordor", id: 6, bigIcon: "STANDARD:mordor.png", smallIcon: "STANDARD:mordor.png")
        ]
    }

    public static func standardBfme2Factions() -> [BfmeFaction] {
        [
            BfmeFaction(name: "Men", id: 3, bigIcon: "STANDARD:men.png", smallIcon: "STANDARD:men.png"),
            BfmeFaction(name: "Elves", id: 5, bigIcon: "STANDARD:elves.png", smallIcon: "STANDARD:elves.png"),
            BfmeFaction(name: "Dwarves", id: 6, bigIcon: "STANDARD:dwarves.png", smallIcon: "STANDARD:dwarves.png"),
            BfmeFaction(name: "Isengard", id: 7, bigIcon: "STANDARD:isengard.png", smallIcon: "STANDARD:isengard.png"),
            BfmeFaction(name: "Mordor", id: 8, bigIcon: "STANDARD:mordor.png", smallIcon: "STANDARD:mordor.png"),
            BfmeFaction(name: "Goblins", id: 9, bigIcon: "STANDARD:goblins.png", smallIcon: "STANDARD:goblins.png")
        ]
    }

    public static func standardRotWkFactions() -> [BfmeFaction] {
        [
            BfmeFaction(name: "Men", id: 3, bigIcon: "STANDARD:men.png", smallIcon: "STANDARD:men.png"),
            BfmeFaction(name: "Elves", id: 5, bigIcon: "STANDARD:elves.png", smallIcon: "STANDARD:elves.png"),
            BfmeFaction(name: "Dwarves", id: 6, bigIcon: "STANDARD:dwarves.png", smallIcon: "STANDARD:dwarves.png"),
            BfmeFaction(name: "Isengard", id: 7, bigIcon: "STANDARD:isengard.png", smallIcon: "STANDARD:isengard.png"),
            BfmeFaction(name: "Mordor", id: 8, bigIcon: "STANDARD:mordor.png", smallIcon: "STANDARD:mordor.png"),
            BfmeFaction(name: "Goblins", id: 9, bigIcon: "STANDARD:goblins.png", smallIcon: "STANDARD:goblins.png"),
            BfmeFaction(name: "Angmar", id: 10, bigIcon: "STANDARD:angmar.png", smallIcon: "STANDARD:angmar.png")
        ]
    }
}
