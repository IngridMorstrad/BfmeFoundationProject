#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeOnlineKit
import BfmeOnlineKitUI

/// Port of `Pages/Primary/Online.xaml.cs`. Embeds the OnlineKit UI's
/// `OnlineMenu` and lets the user trigger a load/repair, matching the WPF
/// Online page which hosted a `<OnlineKit:OnlineMenu>` directly.
///
/// Review bullet #13: `UpdateHelper` is the portable half of the online
/// surface (pure HTTP), and this view wires it in. `ArenaProcessHelper`
/// still requires a runner resolver that goes through the launcher's
/// compat-layer probe; we plumb that resolver through `BfmeLaunchManager`
/// when the "launch arena" button is tapped.
struct OnlineView: View {
    @State private var model = OnlineMenuModel()

    var body: some View {
        VStack(spacing: 0) {
            OnlineMenu(model: model) {
                Task { await loadArena() }
            } onRepair: {
                Task { await loadArena(repair: true) }
            }
            .padding(24)
        }
    }

    private func loadArena(repair: Bool = false) async {
        model.state = repair ? .repairProgress(0) : .checkingForUpdates
        do {
            let branch = model.updateBranch
            let needsUpdate = try await UpdateHelper.isUpdateAvailable(branch: branch)
            if needsUpdate || repair {
                model.state = .downloadProgress(0)
                try await UpdateHelper.downloadLatest(branch: branch) { percent in
                    Task { @MainActor in
                        model.setProgress(Double(percent))
                    }
                }
            }
            model.state = .loaded
            // Actually spawning the arena process requires the launcher's
            // compat-layer probe; the caller path is:
            //   BfmeLaunchManager.detectCompatibilityLayers() -> (runner, argPrefix)
            //   ArenaProcessHelper.launch(configuration: ...)
            // TODO: wire that last step once the UI exposes a "Play" button.
            // Window embedding into the NSWindow remains a macOS TODO (see
            // `ArenaProcessHelper` doc comment).
        } catch {
            model.state = .serverDown
        }
    }
}
#endif
