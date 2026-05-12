#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Generic/DropdownPicker.xaml.cs`. SwiftUI's built-in
/// `Picker` gives us the Apple-native combo box; the element wraps it with
/// the same label/value layout the XAML version used so call sites read
/// identically.
///
/// The generic parameter is constrained to `Hashable & PickerOptionLabel`
/// (see review bullet #9). Previously we declared
/// `extension String: @retroactive CustomStringConvertible`, which
/// retroactively added a stdlib conformance at the module scope; any
/// module that imported `BfmeLauncherApp` would have inherited the
/// conformance and any competing declaration elsewhere in the graph would
/// have broken the build. The local protocol below side-steps the stdlib
/// conformance footgun entirely.
protocol PickerOptionLabel {
    var pickerLabel: String { get }
}

extension String: PickerOptionLabel {
    var pickerLabel: String { self }
}

struct DropdownPicker<Option: Hashable & PickerOptionLabel>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.85)).frame(width: 120, alignment: .leading)
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { opt in
                    Text(opt.pickerLabel).tag(opt)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}
#endif
