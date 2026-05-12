#if canImport(SwiftUI)
import SwiftUI
import Observation
import BfmeOnlineKit

/// SwiftUI port of `OnlineMenu.xaml`. The original WPF control had a single
/// `LoadingOrLoaded` + `Loading` bool pair and a `SetVisualState` switch that
/// flipped nine distinct UI configurations. We mirror that via an
/// `OnlineMenuState` enum and a view model. The view itself is intentionally
/// minimal: it renders a stack of sub-views for each visual state and wires
/// the Arena download/update flow (which actually runs on macOS) through
/// `BfmeOnlineKit.ArenaDataHelper` + `FirewallHelper`. The native Arena
/// binary is Windows-only, so the "launch" step is a hand-off to the Wine/
/// CrossOver/Whisky launcher instead of `Process.Start`.
public enum OnlineMenuVisualState: Sendable, Equatable {
    case designer
    case unloaded
    case checkingForUpdates
    case loading
    case downloadProgress(Double)
    case updateProgress(Double)
    case repairProgress(Double)
    case loaded
    case serverDown
}

@MainActor
@Observable
public final class OnlineMenuModel {
    public var state: OnlineMenuVisualState = .unloaded
    public var updateBranch: String = "main"
    public var accessToken: String = ""
    public var progress: Double = 0

    public init() {}

    public func setProgress(_ newValue: Double) {
        progress = newValue
        switch state {
        case .downloadProgress: state = .downloadProgress(newValue)
        case .updateProgress: state = .updateProgress(newValue)
        case .repairProgress: state = .repairProgress(newValue)
        default: break
        }
    }
}

public struct OnlineMenu: View {
    @Bindable public var model: OnlineMenuModel
    public var onReload: (() -> Void)?
    public var onRepair: (() -> Void)?

    public init(
        model: OnlineMenuModel,
        onReload: (() -> Void)? = nil,
        onRepair: (() -> Void)? = nil
    ) {
        self.model = model
        self.onReload = onReload
        self.onRepair = onRepair
    }

    public var body: some View {
        CornerAccentFrame(color: .white.opacity(0.65), accentLength: 22, lineWidth: 2) {
            ZStack {
                Color.black.opacity(0.55)
                switch model.state {
                case .designer:
                    statusLabel("DESIGN MODE", withButtons: false)
                case .unloaded:
                    statusLabel("NOT LOADED", withButtons: true, loadLabel: "LOAD")
                case .checkingForUpdates:
                    loadingLabel("CHECKING FOR UPDATES")
                case .loading:
                    loadingLabel("LOADING")
                case .downloadProgress(let p):
                    progressLabel("DOWNLOADING", progress: p)
                case .updateProgress(let p):
                    progressLabel("UPDATING", progress: p)
                case .repairProgress(let p):
                    progressLabel("REPAIRING", progress: p)
                case .loaded:
                    EmptyView()
                case .serverDown:
                    statusLabel("COULDN'T CHECK FOR UPDATES", withButtons: true, loadLabel: "RETRY", includeRepair: false)
                }
            }
        }
    }

    @ViewBuilder
    private func statusLabel(_ text: String, withButtons: Bool, loadLabel: String = "LOAD", includeRepair: Bool = true) -> some View {
        VStack(spacing: 18) {
            Text(text)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            if withButtons {
                HStack(spacing: 12) {
                    if includeRepair, let onRepair {
                        Button("REPAIR", action: onRepair)
                    }
                    if let onReload {
                        Button(loadLabel, action: onReload)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func loadingLabel(_ mode: String) -> some View {
        VStack(spacing: 16) {
            LoadingSpinner(isLoading: .constant(true), size: 40)
            Text(mode)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func progressLabel(_ mode: String, progress: Double) -> some View {
        VStack(spacing: 14) {
            Text(mode)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            ProgressBar(progress: progress / 100)
                .frame(width: 260)
            Text("\(Int(progress))%")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
#endif
