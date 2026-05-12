import Foundation

public struct BfmeSpot: Equatable, Hashable, Sendable {
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
}
