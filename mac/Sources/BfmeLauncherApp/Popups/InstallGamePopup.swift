#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeOnlineKitUI

/// Port of `Popups/InstallGamePopup.xaml.cs`. On macOS the "drives" list the
/// WPF version showed is replaced by the user's home directory + Application
/// Support; the user picks where to materialize the install path.
struct InstallGamePopup: PopupBody {
    @State private var selectedLanguage: String = "English"
    @State private var selectedLocation: String = FileManager.default.homeDirectoryForCurrentUser.path

    var onSubmit: (([String]) -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("INSTALL GAME").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)

            DropdownPicker(title: "Language",
                           options: ["English","German","French","Spanish","Italian"],
                           selection: $selectedLanguage)

            HStack {
                Text("Install location:").foregroundStyle(.white.opacity(0.8))
                Text(selectedLocation).foregroundStyle(.white)
                Spacer()
                Button("Choose") {
                    #if canImport(AppKit)
                    // Review bullet #8 fix: `runModal()` on the main actor
                    // blocks the SwiftUI view tree until the picker closes,
                    // making the whole window freeze mid-popup. Switching
                    // to `begin(completionHandler:)` runs the picker on the
                    // main run loop while letting the SwiftUI scene
                    // continue to redraw.
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.begin { response in
                        if response == .OK, let url = panel.url {
                            selectedLocation = url.path
                        }
                    }
                    #endif
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Install") { submit(selectedLanguage, selectedLocation) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 480, maxWidth: 640)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
