#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Generic/Selectable.xaml.cs`. A highlightable card
/// container. Used by the install-location chooser and the per-game tabs.
struct Selectable<Title: View>: View {
    let selected: Bool
    @ViewBuilder let title: () -> Title
    let onTap: () -> Void

    init(selected: Bool, @ViewBuilder title: @escaping () -> Title, onTap: @escaping () -> Void) {
        self.selected = selected
        self.title = title
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            title()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color(red: 21/255, green: 167/255, blue: 233/255).opacity(0.15) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? Color(red: 21/255, green: 167/255, blue: 233/255) : .white.opacity(0.1), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
#endif
