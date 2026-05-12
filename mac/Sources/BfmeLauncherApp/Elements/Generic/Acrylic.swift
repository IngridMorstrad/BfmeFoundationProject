#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit

/// Port of `Elements/Generic/Acrylic.xaml.cs`. WPF used a Win32 blur-behind;
/// on macOS we bridge `NSVisualEffectView` to get the same "frosted glass"
/// look.
struct Acrylic: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.layer?.cornerRadius = cornerRadius
    }
}
#endif
