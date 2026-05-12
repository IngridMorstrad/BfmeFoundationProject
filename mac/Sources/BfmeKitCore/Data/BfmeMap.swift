import Foundation

public struct BfmeMap: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var game: Int
    public var preview: String
    public var width: Float
    public var height: Float
    public var spots: [BfmeSpot]

    public init(id: String, name: String, game: Int, preview: String, width: Float, height: Float, spots: [BfmeSpot]) {
        self.id = id
        self.name = name
        self.game = game
        self.preview = preview
        self.width = width
        self.height = height
        self.spots = spots
    }

    public mutating func randomizeSpots() {
        spots.shuffle()
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case game = "Game"
        case preview = "Preview"
        case width = "Width"
        case height = "Height"
        case spots = "Spots"
    }
}
