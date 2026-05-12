#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Offline/EnabledEnhancementTile.xaml.cs`. A compact tile
/// shown for each active enhancement on the Offline page.
struct EnabledEnhancementTile: View {
    let title: String
    let disable: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 21/255, green: 167/255, blue: 233/255)).frame(width: 8, height: 8)
            Text(title).foregroundStyle(.white).font(.system(size: 13, weight: .medium))
            Spacer()
            Button(action: disable) { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.6)) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.06), in: Capsule())
    }
}
#endif
