#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeOnlineKitUI

/// Port of `Popups/ScriptedPackagePopup.xaml.cs`. Lists the missing
/// requirements for a scripted workshop package as individual requirement
/// rows (`ScriptedPackageRequirementItem`).
struct ScriptedPackagePopup: PopupBody {
    let packageTitle: String
    let requirements: [String]

    var onSubmit: (([String]) -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(packageTitle).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            Text("Missing Requirements")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            VStack(spacing: 6) {
                ForEach(requirements, id: \.self) { req in
                    ScriptedPackageRequirementItem(text: req)
                }
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                Button("Install") { submit("install") }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 480, maxWidth: 680)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
