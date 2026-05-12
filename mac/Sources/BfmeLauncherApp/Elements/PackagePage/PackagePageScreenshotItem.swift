#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/PackagePage/PackagePageScreenshotItem.xaml.cs`.
struct PackagePageScreenshotItem: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                Rectangle().fill(.white.opacity(0.05))
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Rectangle().fill(.red.opacity(0.2))
            @unknown default:
                Rectangle().fill(.white.opacity(0.05))
            }
        }
        .frame(width: 220, height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
#endif
