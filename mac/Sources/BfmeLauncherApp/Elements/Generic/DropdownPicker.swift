#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Generic/DropdownPicker.xaml.cs`. SwiftUI's built-in
/// `Picker` gives us the Apple-native combo box; the element wraps it with
/// the same label/value layout the XAML version used so call sites read
/// identically.
struct DropdownPicker<Option: Hashable & CustomStringConvertible>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.85)).frame(width: 120, alignment: .leading)
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { opt in
                    Text(opt.description).tag(opt)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

extension String: @retroactive CustomStringConvertible {
    public var description: String { self }
}
#endif
