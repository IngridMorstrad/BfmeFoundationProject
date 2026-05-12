#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Pages/Subpages/Settings/Bfme/SettingsBfmeGeneral.xaml.cs`.
/// Surfaces the per-game language/resolution controls that used to live in
/// the WPF settings page.
struct SettingsBfmeGeneralView: View {
    @Environment(AppState.self) private var appState
    @State private var resolution: SystemDisplayManager.Size = SystemDisplayManager.getPrimaryScreenResolution()
    @State private var allResolutions: [SystemDisplayManager.Size] = SystemDisplayManager.getAllSupportedResolutions()
    @State private var language: String = "English"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Game Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Picker("Game", selection: Binding(
                    get: { appState.selectedGame },
                    set: { appState.selectedGame = $0 }
                )) {
                    ForEach(BfmeGame.allCases.filter { $0 != .none }, id: \.self) { g in
                        Text(g.displayName).tag(g)
                    }
                }
                Picker("Resolution", selection: $resolution) {
                    ForEach(allResolutions, id: \.self) { r in
                        Text("\(r.width) x \(r.height)").tag(r)
                    }
                }
                DropdownPicker(title: "Language", options: ["English","German","French","Spanish","Italian"], selection: $language)
            }
            .padding(20)
        }
    }
}
#endif
