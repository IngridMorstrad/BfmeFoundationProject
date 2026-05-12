#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Menues/ContextMenuButtonItem.cs`. A labelled action row
/// for a custom SwiftUI context menu. SwiftUI's `Menu` already handles the
/// hosting; this helper just enforces the launcher's visual style.
struct ContextMenuButtonItem: View {
    let label: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(label, systemImage: systemImage)
            } else {
                Text(label)
            }
        }
    }
}
#endif
