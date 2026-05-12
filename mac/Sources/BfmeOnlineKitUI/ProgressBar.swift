#if canImport(SwiftUI)
import SwiftUI

/// SwiftUI port of `ProgressBar.xaml`. A determinate horizontal bar whose
/// fill width smoothly animates between updates, matching the WPF version's
/// `DoubleAnimation`/`GradientStop.Offset` behaviour.
public struct ProgressBar: View {
    /// Progress fraction in the range 0...1 (matching the XAML version's
    /// `Progress` double property which stored percentage/100).
    public var progress: Double
    public var trackColor: Color
    public var fillColor: Color
    public var height: CGFloat

    public init(
        progress: Double,
        trackColor: Color = Color.white.opacity(0.15),
        fillColor: Color = Color(red: 21/255, green: 167/255, blue: 233/255),
        height: CGFloat = 6
    ) {
        self.progress = max(0, min(1, progress))
        self.trackColor = trackColor
        self.fillColor = fillColor
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(fillColor)
                    .frame(width: geo.size.width * progress)
                    .animation(.easeInOut(duration: progress == 0 ? 0 : 0.5), value: progress)
            }
        }
        .frame(height: height)
    }
}
#endif
