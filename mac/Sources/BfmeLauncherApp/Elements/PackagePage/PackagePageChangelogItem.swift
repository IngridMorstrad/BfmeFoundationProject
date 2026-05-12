#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/PackagePage/PackagePageChangelogItem.xaml.cs`. Renders a
/// single package changelog entry as a scrollable monospaced block.
struct PackagePageChangelogItem: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .padding(10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }
}
#endif
