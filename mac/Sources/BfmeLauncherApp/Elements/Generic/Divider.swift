#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Generic/Divider.xaml.cs`: a thin horizontal line with an
/// optional gradient fade to match the XAML `DividerStyle`.
struct ThinDivider: View {
    var color: Color = .white.opacity(0.2)
    var thickness: CGFloat = 1

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: thickness)
    }
}
#endif
