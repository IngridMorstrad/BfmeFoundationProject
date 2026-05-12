#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Generic/SmoothScrollViewer.cs`. SwiftUI's `ScrollView`
/// already does momentum/elastic scrolling natively on macOS, so this
/// wrapper just re-exports it under the original name for drop-in
/// replacement at call sites.
struct SmoothScrollViewer<Content: View>: View {
    let content: () -> Content
    var axes: Axis.Set = .vertical

    init(axes: Axis.Set = .vertical, @ViewBuilder content: @escaping () -> Content) {
        self.axes = axes
        self.content = content
    }

    var body: some View {
        ScrollView(axes) {
            content()
        }
    }
}
#endif
