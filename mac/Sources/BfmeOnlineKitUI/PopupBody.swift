#if canImport(SwiftUI)
import SwiftUI

/// SwiftUI replacement for the C# `PopupBody` abstract class. A popup is a
/// plain `View` that exposes a `Submit(args)` callback and a `Dismiss`
/// callback; the hosting `PopupVisualizer` injects both.
public protocol PopupBody: View {
    /// Invoked when the popup confirms with data (the C# version passed a
    /// `string[]` — we mirror that as `[String]`).
    var onSubmit: (([String]) -> Void)? { get set }

    /// Invoked when the popup is dismissed without submitting.
    var onClose: (() -> Void)? { get set }
}

public extension PopupBody {
    /// Convenience helper mirroring `PopupBody.Submit(params string[])`.
    func submit(_ values: String...) {
        onSubmit?(values)
        onClose?()
    }

    /// Convenience helper mirroring `PopupBody.Dismiss()`.
    func dismiss() {
        onClose?()
    }
}
#endif
