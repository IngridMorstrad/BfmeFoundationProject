#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeOnlineKitUI

/// Port of `Popups/PackagePagePopup.xaml.cs`. Shows the detail page for a
/// workshop package: header, description, screenshot library, changelog.
struct PackagePagePopup: PopupBody {
    let title: String
    let descriptionText: String
    let screenshots: [URL]
    let changelog: String

    var onSubmit: (([String]) -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Button("Close") { dismiss() }
            }
            PackagePageScreenshotLibrary(screenshots: screenshots)
            Text(descriptionText).foregroundStyle(.white.opacity(0.9))
            Divider()
            PackagePageChangelogItem(text: changelog)
        }
        .padding(24)
        .frame(minWidth: 640, maxWidth: 900)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
