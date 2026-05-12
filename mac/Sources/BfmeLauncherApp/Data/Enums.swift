import Foundation
import BfmeKitCore

/// Re-exports `BfmeKitCore.BfmeGame` so existing call sites that use an
/// unqualified `BfmeGame` continue to compile. Removing the launcher's
/// duplicate enum fixes the silent divergence review bullet #1: the old
/// copy used `none = 3` while `BfmeKitCore.BfmeGame` uses `none = -1`, so
/// cross-module calls that passed the sentinel through `rawValue` landed on
/// different states depending on which module resolved the name. There is
/// now exactly one definition.
public typealias BfmeGame = BfmeKitCore.BfmeGame

extension BfmeGame {
    /// Human-readable label used in the launcher UI. Kept as an extension
    /// so the portable core module stays free of launcher-specific copy.
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
