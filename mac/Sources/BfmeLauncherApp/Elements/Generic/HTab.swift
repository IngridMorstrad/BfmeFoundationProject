#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Generic/HTab.xaml.cs`. A single horizontal tab label.
/// Consumed by `HTabs` and keyed by a `Hashable` id so switching produces a
/// strongly-typed selection.
struct HTab<ID: Hashable>: View {
    let id: ID
    let label: String

    var body: some View {
        // The actual rendering happens inside HTabs; this value-type wrapper
        // just carries the id + label pair.
        Text(label)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}
#endif
