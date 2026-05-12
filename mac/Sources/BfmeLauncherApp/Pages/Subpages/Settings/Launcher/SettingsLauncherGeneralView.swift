#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Pages/Subpages/Settings/Launcher/SettingsLauncherGeneral.xaml.cs`.
struct SettingsLauncherGeneralView: View {
    @State private var hideToTrayOnClose: Bool = false
    @State private var languageIndex: Int = 0

    private let languages: [String] = [
        "English","German","Hungarian","French","Italian","Spanish","Swedish",
        "Turkish","Dutch","Polish","Norwegian","Russian","Arabic"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Launcher Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Toggleable("Hide to tray on close", isOn: $hideToTrayOnClose)
                    .onChange(of: hideToTrayOnClose) { _, newValue in
                        try? LauncherStateManager.setValue(newValue ? "1" : "0",
                                                           for: LauncherStateManager.hideToTrayOnCloseKey)
                    }

                DropdownPicker(title: "Language", options: languages, selection: Binding(
                    get: { languages[safe: languageIndex] ?? "English" },
                    set: { newValue in
                        languageIndex = languages.firstIndex(of: newValue) ?? 0
                        try? LauncherStateManager.setValue("\(languageIndex)",
                                                           for: LauncherStateManager.launcherLanguageKey)
                    }
                ))
            }
            .padding(20)
        }
        .onAppear {
            hideToTrayOnClose = LauncherStateManager.value(for: LauncherStateManager.hideToTrayOnCloseKey) == "1"
            languageIndex = Int(LauncherStateManager.value(for: LauncherStateManager.launcherLanguageKey, default: "0")) ?? 0
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
