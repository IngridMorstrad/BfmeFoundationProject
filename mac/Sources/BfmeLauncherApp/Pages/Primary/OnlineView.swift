#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeOnlineKitUI

/// Port of `Pages/Primary/Online.xaml.cs`. Embeds the OnlineKit UI's
/// `OnlineMenu` and lets the user trigger a load/repair, matching the WPF
/// Online page which hosted a `<OnlineKit:OnlineMenu>` directly.
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
        // Real download/update logic lives in BfmeOnlineKit.UpdateHelper; this
        // method is the glue point the full macOS build will wire up once the
        // Arena binary exists on macOS.
    }
}
#endif
