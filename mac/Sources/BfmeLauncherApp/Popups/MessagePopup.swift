#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeOnlineKitUI

/// Port of `Popups/MessagePopup.xaml.cs`.
struct MessagePopup: PopupBody {
    let title: String
    let message: String
    var onSubmit: (([String]) -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            Text(message).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
            Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(minWidth: 360, maxWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
