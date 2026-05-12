#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Library/LibraryTile.xaml.cs`. Grid tile showing a
/// workshop package + a play button. Used on the Offline Library page.
struct LibraryTile: View {
    let title: String
    let subtitle: String
    var isActive: Bool = false
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(Image(systemName: "play.fill").foregroundStyle(.white.opacity(0.5)).font(.system(size: 28)))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            Button(action: onPlay) {
                Label(isActive ? "Play" : "Activate", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
#endif
