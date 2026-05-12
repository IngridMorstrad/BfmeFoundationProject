#if canImport(SwiftUI)
import SwiftUI

/// SwiftUI port of `CornerAccentFrame.xaml`: four small accent strokes drawn
/// at each corner of the rectangle to give the Arena-style "military" panel
/// look. The frame wraps its `content` and overlays the accents on top.
public struct CornerAccentFrame<Content: View>: View {
    public var color: Color
    public var accentLength: CGFloat
    public var lineWidth: CGFloat
    public var cornerInset: CGFloat
    public var content: () -> Content

    public init(
        color: Color = .white,
        accentLength: CGFloat = 18,
        lineWidth: CGFloat = 2,
        cornerInset: CGFloat = 2,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.color = color
        self.accentLength = accentLength
        self.lineWidth = lineWidth
        self.cornerInset = cornerInset
        self.content = content
    }

    public var body: some View {
        content()
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    Path { path in
                        let inset = cornerInset
                        // Top-left
                        path.move(to: CGPoint(x: inset, y: inset + accentLength))
                        path.addLine(to: CGPoint(x: inset, y: inset))
                        path.addLine(to: CGPoint(x: inset + accentLength, y: inset))
                        // Top-right
                        path.move(to: CGPoint(x: w - inset - accentLength, y: inset))
                        path.addLine(to: CGPoint(x: w - inset, y: inset))
                        path.addLine(to: CGPoint(x: w - inset, y: inset + accentLength))
                        // Bottom-right
                        path.move(to: CGPoint(x: w - inset, y: h - inset - accentLength))
                        path.addLine(to: CGPoint(x: w - inset, y: h - inset))
                        path.addLine(to: CGPoint(x: w - inset - accentLength, y: h - inset))
                        // Bottom-left
                        path.move(to: CGPoint(x: inset + accentLength, y: h - inset))
                        path.addLine(to: CGPoint(x: inset, y: h - inset))
                        path.addLine(to: CGPoint(x: inset, y: h - inset - accentLength))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
                }
            }
    }
}
#endif
