#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/PackagePage/PackagePageScreenshotLibrary.xaml.cs`.
struct PackagePageScreenshotLibrary: View {
    let screenshots: [URL]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(screenshots, id: \.self) { url in
                    PackagePageScreenshotItem(url: url)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
#endif
