#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeOnlineKitUI

/// Port of `Popups/LauncherChangelogPopup.xaml.cs`.
struct LauncherChangelogPopup: PopupBody {
    var onSubmit: (([String]) -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LAUNCHER CHANGELOG").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            ScrollView {
                Text("""
                · Native macOS Apple Silicon rewrite.
                · SwiftUI shell, Workshop + OnlineKit ported.
                · DirectX runtime survey runs as part of startup.
                """)
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            HStack {
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 460, maxWidth: 620)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
