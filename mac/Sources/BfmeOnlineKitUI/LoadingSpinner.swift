#if canImport(SwiftUI)
import SwiftUI

/// SwiftUI port of `LoadingSpinner.xaml`. A continuously rotating circular
/// indicator that spins while `isLoading` is true.
public struct LoadingSpinner: View {
    @Binding public var isLoading: Bool
    public var size: CGFloat
    public var lineWidth: CGFloat
    public var color: Color

    @State private var rotation: Double = 0

    public init(
        isLoading: Binding<Bool>,
        size: CGFloat = 32,
        lineWidth: CGFloat = 3,
        color: Color = .white
    ) {
        self._isLoading = isLoading
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
    }

    public var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .opacity(isLoading ? 1 : 0)
            .onAppear {
                if isLoading { startSpinning() }
            }
            .onChange(of: isLoading) { _, newValue in
                if newValue { startSpinning() }
            }
    }

    private func startSpinning() {
        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}
#endif
