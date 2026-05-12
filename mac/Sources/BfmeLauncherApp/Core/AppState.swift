import Foundation
import Observation

/// Identity of a popup live in the AppState stack. The payload is held as an
/// `Any` so this file stays portable: the SwiftUI view type sits in the
/// `Popups/` directory which is gated by `#if canImport(SwiftUI)`. On Linux
/// the stack is still exercised by `AppStateTests`, just without a view.
public struct PopupEntry: Identifiable, Sendable {
    public let id: UUID
    public let kind: String
    public let view: @Sendable () -> Any

    public init(kind: String, id: UUID = UUID(), view: @escaping @Sendable () -> Any) {
        self.id = id
        self.kind = kind
        self.view = view
    }
}

/// Replaces `LauncherStateManager.cs` and the various `MainWindow` static
/// hooks (`SetContent`, `ShowOffline`, etc.). A single observable store the
/// whole app reads from.
///
/// The class is portable: it uses only Foundation and `Observation`. The
/// SwiftUI views that observe it live in separate, platform-gated files.
@MainActor
@Observable
public final class AppState {
    public var currentTab: PrimaryTab = .offline
    public var selectedGame: BfmeGame = .bfme1

    /// Popup stack (LIFO). The on-screen popup is `popupStack.last`; earlier
    /// entries resume once the top popup is dismissed.
    public private(set) var popupStack: [PopupEntry] = []

    /// Queue of pending popups that arrive while another popup is already
    /// hosted. Mirrors `PopupVisualizer.PopupQueue` in the WPF source.
    public private(set) var popupQueue: [PopupEntry] = []

    /// True while a BfmeWorkshopSyncManager sync is in flight. Disables the
    /// Offline tab's controls and the Settings gear, matching
    /// `MainWindow.OnSyncBegin` / `OnSyncEnd`.
    public var isSyncing: Bool = false

    /// Launcher language index (mirrors `LauncherStateManager.Language`).
    public var launcherLanguage: Int = 0

    public init() {}

    // MARK: - Tab switching

    public func selectTab(_ tab: PrimaryTab) {
        currentTab = tab
    }

    // MARK: - Popup stack

    @discardableResult
    public func present(_ popup: PopupEntry) -> UUID {
        if popupStack.isEmpty {
            popupStack.append(popup)
        } else {
            popupQueue.append(popup)
        }
        return popup.id
    }

    public func dismissTopPopup() {
        guard !popupStack.isEmpty else { return }
        popupStack.removeLast()
        if !popupQueue.isEmpty {
            let next = popupQueue.removeFirst()
            popupStack.append(next)
        }
    }

    public func dismissAllPopups() {
        popupStack.removeAll()
        popupQueue.removeAll()
    }

    public var currentPopup: PopupEntry? { popupStack.last }

    // MARK: - Sync gate

    public func onSyncBegin() { isSyncing = true }
    public func onSyncEnd() { isSyncing = false }
}
