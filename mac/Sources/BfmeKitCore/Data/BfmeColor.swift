import Foundation

public struct BfmeColor: Equatable, Hashable, Sendable {
    public var name: String
    public var id: Int
    public var previewColor: RGBA

    public init(name: String, id: Int, previewColor: RGBA) {
        self.name = name
        self.id = id
        self.previewColor = previewColor
    }
}
