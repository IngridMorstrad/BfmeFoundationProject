#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Generic/NanoSpinner.xaml.cs`: an even smaller spinner
/// used in single-line status strips.
struct NanoSpinner: View {
    @State private var angle: Double = 0
    var body: some View {
        Circle()
            .trim(from: 0.25, to: 0.85)
            .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
#endif
