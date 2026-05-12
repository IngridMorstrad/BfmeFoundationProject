#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Library/LibraryTileHorizontal.xaml.cs`. Wider, row-sized
/// variant of `LibraryTile`.
struct LibraryTileHorizontal: View {
    let title: String
    let subtitle: String
    let description: String
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 120, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                Text(description).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button(action: onPlay) { Image(systemName: "play.fill") }
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
#endif
