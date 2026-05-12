#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeOnlineKitUI

/// Port of `Popups/YesNoPopup.xaml.cs`.
struct YesNoPopup: PopupBody {
    let title: String
    let message: String
    var noSubmits: Bool = false
    var onSubmit: (([String]) -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            Text(message).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("No") {
                    if noSubmits { submit("false") } else { dismiss() }
                }
                Button("Yes") { submit("true") }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 360, maxWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
