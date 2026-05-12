#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Generic/HTabs.xaml.cs`: a horizontal tab group driven by
/// a bound selection. Children are declared as tuples via the `HTabs {
/// HTab(...) HTab(...) }` DSL in the SwiftUI call sites.
struct HTabs<ID: Hashable>: View {
    @Binding var selection: ID
    private let tabs: [(ID, String)]

    init(selection: Binding<ID>, @HTabsBuilder<ID> content: () -> [(ID, String)]) {
        self._selection = selection
        self.tabs = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { (id, label) in
                Button(action: { selection = id }) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selection == id
                            ? Color(red: 21/255, green: 167/255, blue: 233/255)
                            : .white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.white.opacity(0.06), in: Capsule())
    }
}

@resultBuilder
struct HTabsBuilder<ID: Hashable> {
    static func buildBlock(_ components: HTab<ID>...) -> [(ID, String)] {
        components.map { ($0.id, $0.label) }
    }
}
#endif
