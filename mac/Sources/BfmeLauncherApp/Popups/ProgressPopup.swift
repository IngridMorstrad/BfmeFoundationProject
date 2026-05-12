#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import Observation
import BfmeOnlineKitUI

/// Port of `Popups/ProgressPopup.xaml.cs`. Exposes `loadProgress` (0...100) and
/// a `status` string, identical to the C# DependencyProperty surface.
@Observable
final class ProgressPopupModel {
    var loadProgress: Double = 0
    var status: String = ""
    init() {}
}

struct ProgressPopup: PopupBody {
    let title: String
    let message: String
    var model: ProgressPopupModel
    var onSubmit: (([String]) -> Void)?
    var onClose: (() -> Void)?

    init(title: String, message: String, model: ProgressPopupModel = ProgressPopupModel()) {
        self.title = title
        self.message = message
        self.model = model
    }

    var body: some View {
        @Bindable var bindable = model
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            Text(message).foregroundStyle(.white.opacity(0.85))
            ProgressBar(progress: bindable.loadProgress / 100)
            HStack {
                Text(bindable.status).foregroundStyle(.white.opacity(0.7)).font(.system(size: 12))
                Spacer()
                Text("\(Int(bindable.loadProgress))%").foregroundStyle(.white)
            }
        }
        .padding(24)
        .frame(minWidth: 420, maxWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
