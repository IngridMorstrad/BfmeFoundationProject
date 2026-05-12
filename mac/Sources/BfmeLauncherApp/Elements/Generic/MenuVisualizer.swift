#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// Port of `Elements/Generic/MenuVisualizer.xaml.cs`. Renders a transient
/// toast-style tooltip anchored to a host view. SwiftUI's `.popover` covers
/// the interaction pattern; this wrapper just adds the fade-in + auto-dismiss
/// timer the C# version used.
struct MenuVisualizer<HostLabel: View>: View {
    @Binding var isPresented: Bool
    let message: String
    @ViewBuilder var host: () -> HostLabel

    var body: some View {
        host()
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                Text(message)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            isPresented = false
                        }
                    }
            }
    }
}
#endif
