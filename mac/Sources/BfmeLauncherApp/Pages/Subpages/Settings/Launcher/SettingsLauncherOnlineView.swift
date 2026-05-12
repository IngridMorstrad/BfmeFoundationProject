#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Pages/Subpages/Settings/Launcher/SettingsLauncherOnline.xaml.cs`.
/// Exposes the Arena update branch toggle.
struct SettingsLauncherOnlineView: View {
    @State private var branch: String = "main"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Online / Arena Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                DropdownPicker(title: "Update branch", options: ["main", "beta", "dev"], selection: $branch)
                    .onChange(of: branch) { _, newValue in
                        try? LauncherStateManager.setValue(newValue, for: LauncherStateManager.arenaUpdateBranchKey)
                    }
            }
            .padding(20)
            .onAppear {
                branch = LauncherStateManager.value(for: LauncherStateManager.arenaUpdateBranchKey, default: "main")
            }
        }
    }
}
#endif
