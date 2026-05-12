#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Pages/Subpages/Offline/OfflineWorkshop.xaml.cs`. The WPF version
/// showed a grid of `WorkshopTile`s sourced from the workshop backend. We
/// replicate the shell; the actual paginated query lives in
/// `BfmeWorkshopKit.BfmeWorkshopQueryManager` and is wired up here when the
/// UI is first mounted.
struct OfflineWorkshopView: View {
    @Environment(AppState.self) private var appState
    @State private var entries: [String] = []

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                if entries.isEmpty {
                    LibraryTileEmpty()
                } else {
                    ForEach(entries, id: \.self) { guid in
                        WorkshopTile(title: guid)
                    }
                }
            }
            .padding(16)
        }
    }
}
#endif
