import Foundation

public struct BfmeSpot: Codable, Equatable, Hashable, Sendable {
    public var x: Float
    public var y: Float
    public var team: Int
    public var index: Int

    public init(x: Float, y: Float, team: Int, index: Int) {
        self.x = x
        self.y = y
        self.team = team
        self.index = index
    }

    enum CodingKeys: String, CodingKey {
        case x = "X"
        case y = "Y"
        case team = "Team"
        case index = "Index"
    }
}
