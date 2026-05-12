#if canImport(SwiftUI)
import SwiftUI
import Observation

/// Observable host for popup presentation. Mirrors `PopupVisualizer` in the
/// C# OnlineKit: ShowPopup pushes, HidePopup pops, and multiple pushes
/// queue behind the current one. Bind a single instance to the UI via
/// environment or as an `@State`.
@MainActor
@Observable
public final class OnlineKitPopupHost {
    public private(set) var stack: [AnyPopup] = []
    public private(set) var queue: [AnyPopup] = []

    public init() {}

    public var current: AnyPopup? { stack.last }

    public func show<P: PopupBody>(_ popup: P, onSubmit: (([String]) -> Void)? = nil) {
        var wrapped = popup
        wrapped.onSubmit = onSubmit
        wrapped.onClose = { [weak self] in self?.hide() }
        let erased = AnyPopup(wrapped)
        if stack.isEmpty {
            stack.append(erased)
        } else {
            queue.append(erased)
        }
    }

    public func hide() {
        guard !stack.isEmpty else { return }
        stack.removeLast()
        if let next = queue.first {
            queue.removeFirst()
            stack.append(next)
        }
    }
}

/// Type-erased popup wrapper so the host can store heterogeneous popup views.
public struct AnyPopup: Identifiable {
    public let id = UUID()
    public let view: AnyView

    public init<P: PopupBody>(_ popup: P) {
        self.view = AnyView(popup)
    }
}

#if canImport(AppKit)
import AppKit

/// Bridges `NSVisualEffectView` into SwiftUI so the popup visualizer can blur
/// the content behind the popup, matching the C# `BlurEffect`.
public struct VisualEffectBlur: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#endif

/// SwiftUI wrapper around `OnlineKitPopupHost`. Adds the hosted popup as a
/// full-screen overlay with a translucent, slightly-blurred backdrop that
/// mirrors the WPF `PopupVisualizer` scale+opacity animations.
public struct OnlineKitPopupVisualizer<Content: View>: View {
    @Bindable public var host: OnlineKitPopupHost
    public var content: () -> Content

    public init(host: OnlineKitPopupHost, @ViewBuilder content: @escaping () -> Content) {
        self.host = host
        self.content = content
    }

    public var body: some View {
        ZStack {
            content()
                .blur(radius: host.current == nil ? 0 : 8)

            if let popup = host.current {
                ZStack {
                    #if canImport(AppKit)
                    VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                        .opacity(0.6)
                    #else
                    Color.black.opacity(0.35)
                    #endif
                    popup.view
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.2), value: popup.id)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: host.current?.id)
    }
}
#endif
