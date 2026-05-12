import Foundation
import BfmeOnlineKit

#if canImport(CoreText)
import CoreText
#endif

/// Umbrella namespace for the SwiftUI port of OnlineKit's XAML surface
/// (OnlineMenu / PopupVisualizer / PopupBody / LoadingSpinner / ProgressBar /
/// CornerAccentFrame). Only the namespace constant is portable; every actual
/// view lives in its own file and is gated by `#if canImport(SwiftUI)` so the
/// module compiles (empty) on Linux CI.
public enum BfmeOnlineKitUI {
    public static let moduleVersion = "0.3.0"

    /// Registers the bundled `SegoeUI-VF.ttf` with CoreText so SwiftUI views
    /// can request it by family name. Idempotent: registering the same font
    /// twice is a no-op. Does nothing on platforms that lack CoreText (Linux
    /// CI just skips the call).
    public static func registerBundledFonts() {
        #if canImport(CoreText)
        guard let url = Bundle.module.url(forResource: "SegoeUI-VF", withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.module.url(forResource: "SegoeUI-VF", withExtension: "ttf") else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        #endif
    }
}
