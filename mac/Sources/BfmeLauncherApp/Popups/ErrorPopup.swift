#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import BfmeOnlineKitUI

/// Port of `Popups/ErrorPopup.xaml.cs`.
struct ErrorPopup: PopupBody {
    let error: Error
    var onSubmit: (([String]) -> Void)?
    var onClose: (() -> Void)?

    private var errorTitle: String { String(describing: type(of: error)) }
    private var errorBody: String {
        "\(error.localizedDescription)\n\(String(describing: error))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(errorTitle).font(.system(size: 20, weight: .bold)).foregroundStyle(.red)
            ScrollView {
                Text(errorBody)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            HStack {
                Button("Copy Error") {
                    #if canImport(AppKit)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(errorTitle)\n\(errorBody)", forType: .string)
                    #endif
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, maxWidth: 720)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
