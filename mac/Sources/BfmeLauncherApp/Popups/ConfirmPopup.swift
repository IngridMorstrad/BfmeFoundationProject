#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeOnlineKitUI

/// Port of `Popups/ConfirmPopup.xaml.cs`.
struct ConfirmPopup: PopupBody {
    let title: String
    let message: String
    var cancelSubmits: Bool = false
    var onSubmit: (([String]) -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            Text(message).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Cancel") {
                    if cancelSubmits { submit("false") } else { dismiss() }
                }
                Button("Confirm") { submit("true") }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 360, maxWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
