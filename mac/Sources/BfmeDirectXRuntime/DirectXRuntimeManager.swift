import Foundation
import BfmeKitCore

public enum DirectXRuntimeError: Error {
    case resourceMissing
    case extractionFailed(String)
}

/// Holds the result of probing the host Mac for a Wine-compatible runtime.
public struct DirectXHostSurvey: Equatable, Sendable {
    /// `/Applications/Whisky.app` if present.
    public var whiskyPath: String?
    /// `/Applications/CrossOver.app` if present.
    public var crossOverPath: String?
    /// The Apple Game Porting Toolkit marker directory, if present.
    public var gamePortingToolkitPath: String?

    public var hasAnyRuntime: Bool {
        whiskyPath != nil || crossOverPath != nil || gamePortingToolkitPath != nil
    }

    /// A one-line human-readable description.
    public var summary: String {
        var parts: [String] = []
        if let p = whiskyPath { parts.append("Whisky at \(p)") }
        if let p = crossOverPath { parts.append("CrossOver at \(p)") }
        if let p = gamePortingToolkitPath { parts.append("Game Porting Toolkit at \(p)") }
        if parts.isEmpty { return "No Wine-compatible runtime detected." }
        return "Detected: " + parts.joined(separator: ", ")
    }
}

/// DirectX isn't a thing on macOS. BFME titles run under Wine via Whisky,
/// CrossOver, or Apple's Game Porting Toolkit. This manager:
///   1. Probes the host for those runtimes so the UI can surface what it found.
///   2. Extracts the embedded `dx9_redist.zip` to the user's app-support
///      directory so the user can point it at their Wine prefix themselves.
/// It never invokes `DXSETUP.exe` — that only works inside a Wine prefix,
/// which is outside the scope of this launcher process.
public enum DirectXRuntimeManager {
    private static let dxRuntimeVersion = "v1"

    /// The resource bundle for this module. SwiftPM generates `Bundle.module`
    /// for the target so we resolve the zip from that.
    static var resourceBundle: Bundle { Bundle.module }

    /// Default destination directory: `~/Library/Application Support/BFME Workshop/`.
    static func appSupportDirectory(fileManager: FileManager = .default) -> URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("BFME Workshop", isDirectory: true)
    }

    /// Probe the host for Whisky / CrossOver / Apple Game Porting Toolkit.
    public static func surveyHost(fileManager: FileManager = .default) -> DirectXHostSurvey {
        var survey = DirectXHostSurvey()
        let whisky = "/Applications/Whisky.app"
        if fileManager.fileExists(atPath: whisky) { survey.whiskyPath = whisky }

        let crossover = "/Applications/CrossOver.app"
        if fileManager.fileExists(atPath: crossover) { survey.crossOverPath = crossover }

        // The Apple Game Porting Toolkit ships as a series of artifacts under
        // `~/Applications/Game Porting Toolkit` or `/Applications/Game Porting
        // Toolkit.app` in various installer flows. Check both.
        let gptkCandidates = [
            "/Applications/Game Porting Toolkit.app",
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications")
                .appendingPathComponent("Game Porting Toolkit").path
        ]
        for candidate in gptkCandidates where fileManager.fileExists(atPath: candidate) {
            survey.gamePortingToolkitPath = candidate
            break
        }
        return survey
    }

    /// Ensures the bundled `dx9_redist` archive has been extracted to the
    /// user's app-support directory. Writes a `dx_version.flag` sentinel so
    /// subsequent calls become no-ops.
    ///
    /// Parameters are injectable so tests can point at a sandboxed directory.
    @discardableResult
    public static func ensureRuntimes(
        destination: URL? = nil,
        bundle: Bundle? = nil,
        fileManager: FileManager = .default,
        logger: ((String) -> Void)? = nil
    ) async throws -> DirectXHostSurvey {
        let root = destination ?? appSupportDirectory(fileManager: fileManager)
        let configDir = root.appendingPathComponent("Config", isDirectory: true)
        let directxDir = root.appendingPathComponent("DirectX", isDirectory: true)

        try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: directxDir, withIntermediateDirectories: true)

        let flagURL = configDir.appendingPathComponent("dx_version.flag")
        var installRuntime = true
        if fileManager.fileExists(atPath: flagURL.path),
           let contents = try? String(contentsOf: flagURL, encoding: .utf8) {
            let firstLine = contents.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            if firstLine == dxRuntimeVersion || firstLine.isEmpty {
                installRuntime = false
            }
        }

        let survey = surveyHost(fileManager: fileManager)
        logger?(survey.summary)

        if installRuntime {
            let resolvedBundle = bundle ?? resourceBundle
            guard let resourceURL = resolvedBundle.url(forResource: "dx9_redist", withExtension: "zip") else {
                throw DirectXRuntimeError.resourceMissing
            }

            let destZip = directxDir.appendingPathComponent("dx9_redist.zip")
            if fileManager.fileExists(atPath: destZip.path) {
                try fileManager.removeItem(at: destZip)
            }
            try fileManager.copyItem(at: resourceURL, to: destZip)

            let extractRoot = directxDir.appendingPathComponent("dx9_redist", isDirectory: true)
            if fileManager.fileExists(atPath: extractRoot.path) {
                try fileManager.removeItem(at: extractRoot)
            }
            try fileManager.createDirectory(at: extractRoot, withIntermediateDirectories: true)
            try ZipExtractor.extract(zipURL: destZip, into: extractRoot)
            logger?("Extracted dx9_redist.zip to \(extractRoot.path)")
        }

        try dxRuntimeVersion.appending("\n0").write(to: flagURL, atomically: true, encoding: .utf8)

        return survey
    }
}
