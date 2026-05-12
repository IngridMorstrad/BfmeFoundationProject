#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Workshop/WorkshopTile.xaml.cs`. Grid cell for a workshop
/// package. Clicking opens a PackagePagePopup.
struct WorkshopTile: View {
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(8)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
#endif
