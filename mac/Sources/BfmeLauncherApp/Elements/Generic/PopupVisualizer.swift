#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Generic/PopupVisualizer.xaml.cs` targeted at the
/// AllInOneLauncher's popup stack (see `BfmeOnlineKitUI.OnlineKitPopupVisualizer`
/// for the OnlineKit twin). This variant reads from `AppState.popupStack` and
/// renders the top popup view with a scale+opacity transition.
struct LauncherPopupVisualizer: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let popup = appState.currentPopup,
           let view = popup.view() as? (any View) {
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea()
                AnyView(view)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            .animation(.easeInOut(duration: 0.2), value: popup.id)
        }
    }
}
#endif
