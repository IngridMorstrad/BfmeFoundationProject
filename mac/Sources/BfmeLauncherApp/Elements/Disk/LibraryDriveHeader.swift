#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Disk/LibraryDriveHeader.xaml.cs`. Header row used by the
/// InstallGamePopup to represent each attached volume.
struct LibraryDriveHeader: View {
    let libraryDriveName: String
    let libraryDriveSize: String
    var mini: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image("harddrive", bundle: .module)
                .resizable()
                .scaledToFit()
                .frame(width: mini ? 18 : 24, height: mini ? 18 : 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(libraryDriveName)
                    .font(.system(size: mini ? 12 : 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(libraryDriveSize)
                    .font(.system(size: mini ? 10 : 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
    }
}
#endif
