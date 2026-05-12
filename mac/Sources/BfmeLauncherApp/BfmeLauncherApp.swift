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
        // DirectX runtime survey, check for updates.
        BfmeOnlineKitUI.registerBundledFonts()
        registerLauncherFonts()
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

    /// Pulls the `SegoeUI-VF.ttf` resource out of the launcher's own bundle
    /// (in addition to the OnlineKitUI copy) so every SwiftUI view that
    /// requests "Segoe UI" renders with the shipped font file.
    private func registerLauncherFonts() {
        guard let url = Bundle.module.url(forResource: "SegoeUI-VF", withExtension: "ttf", subdirectory: "Resources/Fonts")
            ?? Bundle.module.url(forResource: "SegoeUI-VF", withExtension: "ttf") else { return }
        #if canImport(CoreText)
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        #endif
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
