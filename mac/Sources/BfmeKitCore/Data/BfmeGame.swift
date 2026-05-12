import Foundation

/// The three BFME titles plus a sentinel. Raw values match the integer game IDs
/// used throughout the original C# tree (BFME1=0, BFME2=1, ROTWK=2).
public enum BfmeGame: Int, Equatable, Hashable, CaseIterable, Sendable, Codable {
    case bfme1 = 0
    case bfme2 = 1
    case rotwk = 2
    case none = -1
}
