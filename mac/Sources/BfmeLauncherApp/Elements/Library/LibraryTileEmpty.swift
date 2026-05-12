#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Library/LibraryTileEmpty.xaml.cs`: placeholder tile shown
/// when a row has fewer real tiles than columns.
struct LibraryTileEmpty: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))
            Text("No packages")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16/9, contentMode: .fit)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}
#endif
