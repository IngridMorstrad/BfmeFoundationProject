import Foundation
import BfmeKit
import BfmeKitCore

/// Native-macOS rewrite of `BfmeLaunchManager.cs`. BFME is a Direct3D-9
/// Windows game; on Apple Silicon it runs inside a compatibility layer:
/// Whisky (Apple's Game Porting Toolkit frontend), CrossOver, Wine, or
/// `wine64` from a homebrew install. This manager resolves the .exe path
/// via `BfmeRegistryManager` and launches it through the detected
/// compatibility layer using `Process()`. When no compatibility layer is
/// installed it surfaces an `InstallGamePopup` with guidance.
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
    /// and the registry lookup can all be swapped out.
    public struct Environment: Sendable {
        public var fileExists: @Sendable (String) -> Bool
        public var installPathForGame: @Sendable (BfmeGame) async -> String
        public var activeModPathForGame: @Sendable (BfmeGame) async -> String
        public var runProcess: @Sendable (_ launchPath: String, _ arguments: [String], _ currentDirectory: String?) throws -> Int32

        public init(
            fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
            installPathForGame: @escaping @Sendable (BfmeGame) async -> String = { game in
                await BfmeRegistryManager.getKeyValue(game.rawValue, .installPath)
            },
            activeModPathForGame: @escaping @Sendable (BfmeGame) async -> String = { _ in "" },
            runProcess: @escaping @Sendable (String, [String], String?) throws -> Int32 = { try Environment.defaultRunProcess($0, $1, $2) }
        ) {
            self.fileExists = fileExists
            self.installPathForGame = installPathForGame
            self.activeModPathForGame = activeModPathForGame
            self.runProcess = runProcess
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

    /// Ordered list of probe locations, mirroring the C# `ProcessStartInfo`
    /// approach of handing off to the OS's launch resolver.
    static let compatibilityProbes: [(CompatibilityLayer, [String])] = [
        (.whisky, [
            "/Applications/Whisky.app",
            "~/Applications/Whisky.app"
        ]),
        (.crossover, [
            "/Applications/CrossOver.app",
            "~/Applications/CrossOver.app"
        ]),
        (.gamePortingToolkit, [
            "/Applications/Game Porting Toolkit.app",
            "/usr/local/Cellar/game-porting-toolkit",
            "/opt/homebrew/Cellar/game-porting-toolkit"
        ]),
        (.wine, [
            "/usr/local/bin/wine",
            "/opt/homebrew/bin/wine",
            "/usr/local/bin/wine64",
            "/opt/homebrew/bin/wine64"
        ])
    ]

    public static func detectCompatibilityLayers(environment: Environment = Environment()) -> [CompatibilityLayer] {
        var found: [CompatibilityLayer] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        for (layer, paths) in compatibilityProbes {
            for rawPath in paths {
                let expanded = rawPath.hasPrefix("~") ? home + String(rawPath.dropFirst()) : rawPath
                if environment.fileExists(expanded) {
                    if !found.contains(layer) { found.append(layer) }
                    break
                }
            }
        }
        return found
    }

    // MARK: - Resolving the game exe

    public struct ResolvedLaunch: Sendable, Equatable {
        public let game: BfmeGame
        public let executablePath: String
        public let workingDirectory: String
        public let arguments: [String]
        public let compatibilityLayer: CompatibilityLayer
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
        guard let layer = layers.first else {
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
            compatibilityLayer: layer
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
    /// `layer`. Public so tests can assert on the command shape without
    /// actually spawning a process.
    public static func runnerCommand(for resolved: ResolvedLaunch) -> (String, [String]) {
        switch resolved.compatibilityLayer {
        case .whisky:
            // Whisky.app ships a CLI wrapper that can run a .exe out of a bottle.
            return ("/Applications/Whisky.app/Contents/Resources/Whisky", [
                "run", resolved.executablePath
            ] + resolved.arguments)
        case .crossover:
            return ("/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine", [
                resolved.executablePath
            ] + resolved.arguments)
        case .gamePortingToolkit:
            // GPTK ships its Wine under Homebrew by default.
            return ("/usr/local/bin/wine64", [resolved.executablePath] + resolved.arguments)
        case .wine:
            return ("/usr/local/bin/wine", [resolved.executablePath] + resolved.arguments)
        }
    }

    // MARK: - Helpers

    private static func joinPath(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if a.hasSuffix("/") || a.hasSuffix(#"\"#) { return a + b }
        return a + "/" + b
    }
}
