import Foundation
import BfmeKit
import BfmeKitCore
import BfmeWorkshopKit

/// Native-macOS rewrite of `BfmeSyncManager.cs`. Orchestrates workshop
/// package downloads plus registry updates. The heavy lifting is in
/// `BfmeWorkshopKit`; this wrapper supplies the glue between AppState
/// (for popup presentation) and the workshop managers.
public enum BfmeSyncManager {
    public struct ProgressUpdate: Sendable {
        public let percent: Int
        public let status: String
        public init(percent: Int, status: String) { self.percent = percent; self.status = status }
    }

    public static func installGame(
        _ game: BfmeGame,
        selectedLanguage: String,
        selectedLocation: String,
        appState: AppState
    ) async {
        await appState.onSyncBegin()
        defer { Task { @MainActor in appState.onSyncEnd() } }

        let leaf = game == .rotwk ? "RotWK" : "BFME\(game.rawValue + 1)"
        let installURL = URL(fileURLWithPath: selectedLocation).appendingPathComponent(leaf)
        do {
            try await BfmeRegistryManager.createNewInstallRegistry(
                game.rawValue,
                installPath: installURL.path,
                language: selectedLanguage
            )
            if game == .rotwk {
                let bfme2Installed = await BfmeRegistryManager.isInstalled(BfmeGame.bfme2.rawValue)
                if !bfme2Installed {
                    let bfme2URL = URL(fileURLWithPath: selectedLocation).appendingPathComponent("BFME2")
                    try await BfmeRegistryManager.createNewInstallRegistry(
                        BfmeGame.bfme2.rawValue,
                        installPath: bfme2URL.path,
                        language: selectedLanguage
                    )
                }
            }
        } catch {
            // Mirrors PopupVisualizer.ShowPopup(new ErrorPopup(ex)).
            await MainActor.run {
                _ = appState.present(PopupEntry(kind: "ErrorPopup") {
                    ErrorPopupPayload(error: error)
                })
            }
        }
    }
}

/// Portable payload carried by the error popup entry. The SwiftUI view
/// implementation reads `error.localizedDescription` at render time.
public struct ErrorPopupPayload: Sendable {
    public let message: String
    public init(error: Error) {
        self.message = String(describing: error)
    }
}
