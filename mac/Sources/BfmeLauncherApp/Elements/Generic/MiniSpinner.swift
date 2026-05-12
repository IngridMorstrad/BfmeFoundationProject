#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Generic/MiniSpinner.xaml.cs`. A small spinner used in
/// list rows and inline controls.
struct MiniSpinner: View {
    @State private var angle: Double = 0
    var size: CGFloat = 16

    var body: some View {
        Circle()
            .trim(from: 0.2, to: 0.9)
            .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
#endif
