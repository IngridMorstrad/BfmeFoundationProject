#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/ScriptedPackage/ScriptedPackageRequirementItem.xaml.cs`.
/// Shows a single missing requirement line item inside `ScriptedPackagePopup`.
struct ScriptedPackageRequirementItem: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(text).foregroundStyle(.white).font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }
}
#endif
