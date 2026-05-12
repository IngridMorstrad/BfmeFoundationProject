import Foundation
import BfmeKit
import BfmeKitCore
import BfmeHttpInstruments
import BfmeDirectXRuntime
import BfmeWorkshopKit
import BfmeOnlineKit
import BfmeOnlineKitUI

#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit

/// Root SwiftUI application. Replaces `App.xaml.cs` + `MainWindow.xaml.cs`.
/// The `@main` attribute is gated behind SwiftUI + AppKit availability so the
/// module can still compile on Linux (where the Linux stub at the bottom of
/// this file picks up the `@main` role instead).
@main
struct BfmeLauncherApp: App {
    @State private var appState = AppState()

    init() {
        // Matches the C# startup order: register custom fonts, kick off a
        // DirectX runtime survey, check for updates. Review bullet #12:
        // SegoeUI-VF.ttf is owned by BfmeOnlineKitUI so every consumer
        // registers it through that bundle; the launcher no longer ships
        // its own copy.
        BfmeOnlineKitUI.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup("BFME All In One Launcher") {
            MainView()
                .environment(appState)
                .frame(minWidth: 1024, minHeight: 640, idealWidth: 1280, idealHeight: 800)
                .task {
                    // Port of `LauncherUpdateManager.CheckForUpdates()` +
                    // `BfmeWorkshopKit.DirectXRuntimeManager.ensureRuntimes()`.
                    try? await DirectXRuntimeManager.ensureRuntimes()
                    _ = await LauncherUpdateManager.fetchLatestVersionHash()
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)
    }
}

#else

/// Linux / headless fallback. Picks up the `@main` role so `swift build` on
/// a platform without SwiftUI + AppKit still links a valid executable.
@main
struct BfmeLauncherApp {
    static func main() {
        print("BFME All In One Launcher (macOS native port)")
        print("This build was produced on a non-macOS host; the SwiftUI app")
        print("is only available when compiled with AppKit + SwiftUI.")
        print("Module versions:")
        print("  BfmeKit         : \(BfmeKit.moduleVersion)")
        print("  BfmeWorkshopKit : \(BfmeWorkshopKit.moduleVersion)")
        print("  BfmeOnlineKit   : \(BfmeOnlineKit.moduleVersion)")
        print("  BfmeOnlineKitUI : \(BfmeOnlineKitUI.moduleVersion)")
        let survey = DirectXRuntimeManager.surveyHost()
        print("DirectX runtime survey: \(survey.summary)")
    }
}

#endif
