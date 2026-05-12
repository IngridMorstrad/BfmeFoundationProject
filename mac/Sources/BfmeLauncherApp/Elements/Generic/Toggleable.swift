#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Generic/Toggleable.xaml.cs`. A labelled toggle row that
/// matches the WPF `Toggleable` control. `Toggle` already gives us the Apple
/// native switch; we just enforce the label-left/switch-right layout.
struct Toggleable: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.9))
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
    }
}
#endif
