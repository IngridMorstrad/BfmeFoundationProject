#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Pages/Primary/Settings.xaml.cs`. Left sidebar selects a settings
/// subpage; right content hosts the actual subpage view.
struct SettingsView: View {
    enum SubSection: String, CaseIterable, Identifiable {
        case bfmeGeneral = "BFME"
        case launcherGeneral = "Launcher"
        case launcherOnline = "Online"
        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @State private var section: SubSection = .launcherGeneral

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SubSection.allCases) { s in
                    Selectable(selected: section == s, title: { Text(s.rawValue) }) {
                        section = s
                    }
                }
                Spacer()
                Button("Close") { appState.selectTab(.offline) }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 12)
            }
            .frame(width: 200)
            .padding(16)
            .background(.black.opacity(0.35))

            Divider().opacity(0.3)

            Group {
                switch section {
                case .bfmeGeneral:    SettingsBfmeGeneralView()
                case .launcherGeneral: SettingsLauncherGeneralView()
                case .launcherOnline:  SettingsLauncherOnlineView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
