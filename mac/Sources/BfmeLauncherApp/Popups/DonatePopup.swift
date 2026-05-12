#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeOnlineKitUI

/// Port of `Popups/DonatePopup.xaml.cs`.
struct DonatePopup: PopupBody {
    var onSubmit: (([String]) -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Text("SUPPORT THE PROJECT").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            Text("If you enjoy BFME All-In-One Launcher, consider supporting development.")
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link(destination: URL(string: "https://www.patreon.com")!) {
                    Image("patreon", bundle: .module).resizable().scaledToFit().frame(height: 36)
                }
                Link(destination: URL(string: "https://www.paypal.com")!) {
                    Image("paypal_horizontal", bundle: .module).resizable().scaledToFit().frame(height: 36)
                }
            }
            Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(minWidth: 420, maxWidth: 540)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
