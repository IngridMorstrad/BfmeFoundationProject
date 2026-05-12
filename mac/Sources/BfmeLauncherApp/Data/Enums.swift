import Foundation

/// Direct port of `src/BfmeFoundationProject_AllInOneLauncher/Data/Enums.cs`.
/// Keeps the same integer backing so the WorkshopKit/BfmeKit APIs (which use
/// `Int` indexed `BfmeGame` values) continue to interoperate without a
/// separate conversion layer.
public enum BfmeGame: Int, Sendable, CaseIterable, Codable {
    case bfme1 = 0
    case bfme2 = 1
    case rotwk = 2
    case none = 3

    public var displayName: String {
        switch self {
        case .bfme1: return "BFME1"
        case .bfme2: return "BFME2"
        case .rotwk: return "RotWK"
        case .none: return "None"
        }
    }
}

/// Top-level navigation tabs in the main window. Mirrors the WPF tab strip
/// defined by `offlineTab` / `onlineTab` / `guidesTab` / `aboutTab` in
/// `MainWindow.xaml` plus the settings gear icon which swaps the full
/// content area.
public enum PrimaryTab: String, Sendable, CaseIterable {
    case offline
    case online
    case guides
    case settings
    case about
}
