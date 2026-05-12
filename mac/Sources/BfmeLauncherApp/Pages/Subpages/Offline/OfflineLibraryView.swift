#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Pages/Subpages/Offline/OfflineLibrary.xaml.cs`. Shows a scrollable
/// grid of `LibraryTile`s representing the active patches + base-game entry
/// for the currently selected game.
struct OfflineLibraryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                LibraryTile(title: "Base Game", subtitle: appState.selectedGame.displayName, isActive: true) {
                    Task { try? await BfmeLaunchManager.launchGame(appState.selectedGame) }
                }
                LibraryTileEmpty()
            }
            .padding(16)
        }
    }
}
#endif
