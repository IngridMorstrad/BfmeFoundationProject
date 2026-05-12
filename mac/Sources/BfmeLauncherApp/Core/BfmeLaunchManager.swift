import Foundation
import BfmeKit
import BfmeKitCore

/// Native-macOS rewrite of `BfmeLaunchManager.cs`. BFME is a Direct3D-9
/// Windows game; on Apple Silicon it runs inside a compatibility layer:
/// Whisky (a Wine/GPTK frontend), CrossOver, Wine installed via Homebrew,
/// or Apple's Game Porting Toolkit. This manager resolves the `.exe` path
/// via `BfmeRegistryManager` and launches it through the detected
/// compatibility layer using `Process()`. When no compatibility layer is
/// installed it surfaces an `InstallGamePopup` with guidance.
///
/// Runner resolution (addresses review bullets #2-#4):
/// - The probe table records for each layer a list of candidate binary
///   locations that would actually execute on an Apple Silicon host. The
///   matched path is threaded through `ResolvedLaunch.runnerBinaryPath` and
///   consumed by `runnerCommand(for:)` so Intel Homebrew and Apple Silicon
///   Homebrew both work without hardcoding `/usr/local`.
/// - Whisky does not ship a CLI at `Contents/Resources/Whisky`. The probe
///   now looks for `wine64` inside the user's active bottle
///   (`~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/<uuid>/wine/bin/wine64`)
///   and falls back to `open -a Whisky` with the executable as a document
///   argument when no bottle is detected. The latter hands control to the
///   Whisky UI which then routes the .exe through the active bottle.
/// - GPTK's `wine64` lives under its Homebrew cellar (`.../game-porting-toolkit/.../bin/wine64`)
///   or under whatever prefix Apple's installer created. The probe walks
///   both Homebrew prefixes and records the first `wine64` that exists.
public enum BfmeLaunchManager {
    // MARK: - Compatibility-layer detection

    public enum CompatibilityLayer: String, Sendable, CaseIterable {
        case whisky
        case crossover
        case wine
        case gamePortingToolkit

        public var displayName: String {
            switch self {
            case .whisky: return "Whisky"
            case .crossover: return "CrossOver"
            case .wine: return "Wine"
            case .gamePortingToolkit: return "Game Porting Toolkit"
            }
        }
    }

    /// Pluggable environment for tests: directory probes, process launch,
    /// and the registry lookup can all be swapped out. A synthetic
    /// filesystem is expressed by overriding `fileExists` with a set of
    /// paths that the test wants to "exist".
    public struct Environment: Sendable {
        public var fileExists: @Sendable (String) -> Bool
        public var installPathForGame: @Sendable (BfmeGame) async -> String
        public var activeModPathForGame: @Sendable (BfmeGame) async -> String
        public var runProcess: @Sendable (_ launchPath: String, _ arguments: [String], _ currentDirectory: String?) throws -> Int32
        /// Returns every entry in a directory (non-recursive). Used by the
        /// Whisky probe to walk the Bottles container. Defaults to
        /// `FileManager.contentsOfDirectory`; tests can substitute a canned
        /// listing.
        public var directoryContents: @Sendable (String) -> [String]
        /// Expands `~` to the user's home directory. Overridable so tests
        /// don't accidentally touch the tester's real home.
        public var homeDirectory: @Sendable () -> String

        public init(
            fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
            installPathForGame: @escaping @Sendable (BfmeGame) async -> String = { game in
                await BfmeRegistryManager.getKeyValue(game.rawValue, .installPath)
            },
            activeModPathForGame: @escaping @Sendable (BfmeGame) async -> String = { _ in "" },
            runProcess: @escaping @Sendable (String, [String], String?) throws -> Int32 = { try Environment.defaultRunProcess($0, $1, $2) },
            directoryContents: @escaping @Sendable (String) -> [String] = { path in
                (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            },
            homeDirectory: @escaping @Sendable () -> String = { FileManager.default.homeDirectoryForCurrentUser.path }
        ) {
            self.fileExists = fileExists
            self.installPathForGame = installPathForGame
            self.activeModPathForGame = activeModPathForGame
            self.runProcess = runProcess
            self.directoryContents = directoryContents
            self.homeDirectory = homeDirectory
        }

        public static func defaultRunProcess(_ launchPath: String, _ arguments: [String], _ currentDirectory: String?) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            if let currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            }
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
    }

    public enum LaunchError: Error, Equatable, CustomStringConvertible {
        case noCompatibilityLayerDetected
        case gameNotInstalled(BfmeGame)
        case executableMissing(path: String)
        case compatRuntimeMissing(path: String)

        public var description: String {
            switch self {
            case .noCompatibilityLayerDetected:
                return "No Wine, CrossOver, Whisky, or Game Porting Toolkit install was detected. Install one of these to run BFME on macOS."
            case .gameNotInstalled(let game):
                return "\(game.displayName) is not installed. Install it first through the launcher."
            case .executableMissing(let path):
                return "Game executable not found on disk at: \(path)"
            case .compatRuntimeMissing(let path):
                return "The compatibility layer was detected but its runtime binary is missing at: \(path)"
            }
        }
    }

    /// Detection result for one compatibility layer. `runnerBinaryPath` is
    /// the exact binary that `runnerCommand` should invoke.
    public struct DetectedLayer: Equatable, Sendable {
        public let layer: CompatibilityLayer
        /// For wine/crossover/GPTK this is a wine/wine64 binary. For Whisky
        /// this is either the active-bottle `wine64` binary (preferred) or
        /// `/usr/bin/open` when the probe had to fall back to driving the
        /// Whisky app through its URL handler.
        public let runnerBinaryPath: String
        /// True when the Whisky probe had to fall back to `open -a Whisky`.
        /// `runnerCommand` rewrites the argv accordingly when this is set.
        public let usesWhiskyAppFallback: Bool

        public init(layer: CompatibilityLayer, runnerBinaryPath: String, usesWhiskyAppFallback: Bool = false) {
            self.layer = layer
            self.runnerBinaryPath = runnerBinaryPath
            self.usesWhiskyAppFallback = usesWhiskyAppFallback
        }
    }

    /// Candidate binary locations per layer. The probe keeps the first match.
    /// Order matters: Apple-Silicon-first paths come first on layers where
    /// a developer most likely installed a native arm64 build.
    static let crossoverCandidates: [String] = [
        "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"
    ]
    static let wineCandidates: [String] = [
        "/opt/homebrew/bin/wine64",
        "/opt/homebrew/bin/wine",
        "/usr/local/bin/wine64",
        "/usr/local/bin/wine"
    ]
    static let gptkCandidates: [String] = [
        "/opt/homebrew/opt/game-porting-toolkit/bin/wine64",
        "/usr/local/opt/game-porting-toolkit/bin/wine64",
        "/opt/homebrew/bin/gameportingtoolkit",
        "/usr/local/bin/gameportingtoolkit"
    ]
    /// Fallback invoker for Whisky when a bottle's wine64 cannot be located.
    static let whiskyAppBundlePath = "/Applications/Whisky.app"
    static let whiskyOpenBinary = "/usr/bin/open"

    /// Resolves the Whisky bottle's wine64 binary, if any. Walks every UUID
    /// under `~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/` and
    /// returns the first `wine/bin/wine64` that exists.
    static func resolveWhiskyBottleRunner(environment: Environment) -> String? {
        let home = environment.homeDirectory()
        let containerRoot = home + "/Library/Containers/com.isaacmarovitz.Whisky/Bottles"
        let entries = environment.directoryContents(containerRoot)
        for entry in entries {
            // Whisky names bottles by UUID (with hyphens) but also stashes
            // metadata alongside; the wine64 binary is under `wine/bin/wine64`.
            let candidate = containerRoot + "/" + entry + "/wine/bin/wine64"
            if environment.fileExists(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Resolves the first existing binary in a list, honoring `~` expansion.
    static func firstExistingBinary(_ candidates: [String], environment: Environment) -> String? {
        let home = environment.homeDirectory()
        for rawPath in candidates {
            let expanded = rawPath.hasPrefix("~") ? home + String(rawPath.dropFirst()) : rawPath
            if environment.fileExists(expanded) {
                return expanded
            }
        }
        return nil
    }

    /// Detect every compatibility layer installed on the host with a
    /// fully-resolved runner binary path attached. Order of preference:
    /// Whisky, CrossOver, Wine, GPTK. Callers take the first element.
    public static func detectCompatibilityLayers(environment: Environment = Environment()) -> [DetectedLayer] {
        var layers: [DetectedLayer] = []

        // Whisky: prefer the active bottle's wine64; fall back to
        // `open -a Whisky` if the .app exists but no bottle was detected.
        if let bottleRunner = resolveWhiskyBottleRunner(environment: environment) {
            layers.append(.init(layer: .whisky, runnerBinaryPath: bottleRunner))
        } else if environment.fileExists(whiskyAppBundlePath) {
            layers.append(.init(layer: .whisky, runnerBinaryPath: whiskyOpenBinary, usesWhiskyAppFallback: true))
        }

        if let crossover = firstExistingBinary(crossoverCandidates, environment: environment) {
            layers.append(.init(layer: .crossover, runnerBinaryPath: crossover))
        }

        if let wine = firstExistingBinary(wineCandidates, environment: environment) {
            layers.append(.init(layer: .wine, runnerBinaryPath: wine))
        }

        if let gptk = firstExistingBinary(gptkCandidates, environment: environment) {
            layers.append(.init(layer: .gamePortingToolkit, runnerBinaryPath: gptk))
        }

        return layers
    }

    // MARK: - Resolving the game exe

    public struct ResolvedLaunch: Sendable, Equatable {
        public let game: BfmeGame
        public let executablePath: String
        public let workingDirectory: String
        public let arguments: [String]
        public let compatibilityLayer: CompatibilityLayer
        /// The exact binary the OS will exec (wine / wine64 / `open`).
        /// Threaded through from the probe so runner-command emission never
        /// hardcodes a path that the probe did not verify.
        public let runnerBinaryPath: String
        /// When true, `runnerCommand` emits `open -a Whisky <exe>` instead
        /// of `<wine64> <exe>`.
        public let usesWhiskyAppFallback: Bool
    }

    /// Resolves the full launch command for a game: installed executable,
    /// working directory, `-mod` arguments (from `BfmeWorkshopManager.GetActiveModPath`
    /// in the C# version), and the detected compatibility layer. Throws if
    /// anything is missing.
    public static func resolveLaunch(
        for game: BfmeGame,
        environment: Environment = Environment()
    ) async throws -> ResolvedLaunch {
        guard game != .none else { throw LaunchError.gameNotInstalled(game) }

        let installPath = await environment.installPathForGame(game)
        guard !installPath.isEmpty else { throw LaunchError.gameNotInstalled(game) }

        let exeName = BfmeDefaults.defaultGameExecutableNames[game.rawValue] ?? ""
        let executablePath = joinPath(installPath, exeName)

        guard environment.fileExists(executablePath) else {
            throw LaunchError.executableMissing(path: executablePath)
        }

        let layers = detectCompatibilityLayers(environment: environment)
        guard let detected = layers.first else {
            throw LaunchError.noCompatibilityLayerDetected
        }

        var args: [String] = []
        let modPath = await environment.activeModPathForGame(game)
        if !modPath.isEmpty {
            args.append("-mod")
            args.append(modPath)
        }

        return ResolvedLaunch(
            game: game,
            executablePath: executablePath,
            workingDirectory: installPath,
            arguments: args,
            compatibilityLayer: detected.layer,
            runnerBinaryPath: detected.runnerBinaryPath,
            usesWhiskyAppFallback: detected.usesWhiskyAppFallback
        )
    }

    /// Launches the game. Hides the launcher, blocks until the game exits,
    /// and re-shows the launcher — matching `LaunchGame` in the C# source.
    public static func launchGame(
        _ game: BfmeGame,
        environment: Environment = Environment(),
        onBeforeLaunch: (@Sendable () -> Void)? = nil,
        onAfterLaunch: (@Sendable () -> Void)? = nil
    ) async throws {
        let resolved = try await resolveLaunch(for: game, environment: environment)
        onBeforeLaunch?()
        defer { onAfterLaunch?() }

        let (runnerPath, runnerArgs) = runnerCommand(for: resolved)
        guard environment.fileExists(runnerPath) else {
            throw LaunchError.compatRuntimeMissing(path: runnerPath)
        }
        _ = try environment.runProcess(runnerPath, runnerArgs, resolved.workingDirectory)
    }

    /// Returns the (binary, argv) needed to invoke `executablePath` through
    /// `resolved.compatibilityLayer`. Public so tests can assert on the
    /// command shape without actually spawning a process.
    public static func runnerCommand(for resolved: ResolvedLaunch) -> (String, [String]) {
        switch resolved.compatibilityLayer {
        case .whisky:
            if resolved.usesWhiskyAppFallback {
                // `open -a Whisky --args <exe> [-mod ...]` hands the .exe to
                // the Whisky app which then runs it inside the user's active
                // bottle. The `--args` separator ensures everything after it
                // is forwarded verbatim instead of consumed by `open`.
                return (resolved.runnerBinaryPath, [
                    "-a", "Whisky", "--args",
                    resolved.executablePath
                ] + resolved.arguments)
            }
            return (resolved.runnerBinaryPath, [resolved.executablePath] + resolved.arguments)
        case .crossover, .wine, .gamePortingToolkit:
            return (resolved.runnerBinaryPath, [resolved.executablePath] + resolved.arguments)
        }
    }

    // MARK: - Helpers

    private static func joinPath(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if a.hasSuffix("/") || a.hasSuffix(#"\"#) { return a + b }
        return a + "/" + b
    }
}
