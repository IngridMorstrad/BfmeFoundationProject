#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Offline/LaunchButton.xaml.cs`. Big play button that
/// fires `BfmeLaunchManager.launchGame` for the currently selected game.
struct LaunchButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            Task { try? await BfmeLaunchManager.launchGame(appState.selectedGame) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text("PLAY").font(.system(size: 18, weight: .bold))
            }
            .frame(minWidth: 180)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
#endif
