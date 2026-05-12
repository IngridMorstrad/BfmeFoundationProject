#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeOnlineKitUI

/// Replaces `MainWindow.xaml` + `MainWindow.xaml.cs`. Hosts the top tab bar
/// (Offline / Online / Guides / Settings / About) and swaps in the matching
/// primary page. Popups sit in an overlay managed by `AppState`.
struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            // Background matches the C# MainWindow.xaml background image.
            backgroundLayer
                .ignoresSafeArea()
                .blur(radius: appState.currentTab == .settings ? 20 : 0)
            VStack(spacing: 0) {
                TopTabBar()
                Divider().opacity(0.3)
                pageBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            popupOverlay
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let _ = Bundle.module.url(forResource: "BGMap", withExtension: "png", subdirectory: "Resources/Images") {
            Image("BGMap", bundle: .module)
                .resizable()
                .scaledToFill()
        } else {
            Color.black
        }
    }

    @ViewBuilder
    private var pageBody: some View {
        switch appState.currentTab {
        case .offline:  OfflineView()
        case .online:   OnlineView()
        case .guides:   GuidesView()
        case .settings: SettingsView()
        case .about:    AboutView()
        }
    }

    @ViewBuilder
    private var popupOverlay: some View {
        if let popup = appState.currentPopup,
           let view = popup.view() as? (any View) {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { /* mirror WPF: click-through disabled */ }
                AnyView(view)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            .animation(.easeInOut(duration: 0.2), value: popup.id)
        }
    }
}

private struct TopTabBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PrimaryTab.allCases.filter { $0 != .settings }, id: \.self) { tab in
                tabLabel(tab)
            }
            Spacer()
            Button(action: { appState.selectTab(.settings) }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .opacity(appState.isSyncing ? 0.4 : 1)
            .disabled(appState.isSyncing)
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
        .background(.black.opacity(0.5))
    }

    @ViewBuilder
    private func tabLabel(_ tab: PrimaryTab) -> some View {
        let selected = appState.currentTab == tab
        Button(action: { appState.selectTab(tab) }) {
            Text(tab.rawValue.uppercased())
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected
                    ? Color(red: 21/255, green: 167/255, blue: 233/255)
                    : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
#endif
