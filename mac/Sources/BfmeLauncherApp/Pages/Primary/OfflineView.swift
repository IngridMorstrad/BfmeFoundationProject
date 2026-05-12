#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Pages/Primary/Offline.xaml.cs`. Hosts the two subpages
/// (OfflineLibrary + OfflineWorkshop) and a launch button per game.
struct OfflineView: View {
    @Environment(AppState.self) private var appState
    @State private var subTab: SubTab = .library

    enum SubTab: Hashable { case library, workshop }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                ForEach(BfmeGame.allCases.filter { $0 != .none }, id: \.self) { game in
                    Selectable(
                        selected: appState.selectedGame == game,
                        title: { Text(game.displayName) }
                    ) {
                        appState.selectedGame = game
                    }
                }
                Spacer()
                HTabs(selection: $subTab) {
                    HTab(id: SubTab.library, label: "LIBRARY")
                    HTab(id: SubTab.workshop, label: "WORKSHOP")
                }
            }
            .padding(16)

            Group {
                switch subTab {
                case .library:  OfflineLibraryView()
                case .workshop: OfflineWorkshopView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(appState.isSyncing)
        .opacity(appState.isSyncing ? 0.6 : 1)
    }
}
#endif
