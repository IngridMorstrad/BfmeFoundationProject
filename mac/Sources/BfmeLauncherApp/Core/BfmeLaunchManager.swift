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
/// Runner resolution (addresses review-v2 bullets #1-#4):
///
/// * The probe table records for each layer a list of candidate binary
///   locations that would actually execute on an Apple Silicon host. The
///   matched path is threaded through `ResolvedLaunch.runnerBinaryPath` and
///   consumed by `runnerCommand(for:)` so Intel Homebrew and Apple Silicon
///   Homebrew both work without hardcoding `/usr/local`.
/// * Whisky 2.x keeps the `wine64` binary SHARED at
///   `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64`
///   (or `.../Libraries/Wine64/bin/wine64`). Per-bottle directories under
///   `~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/<uuid>/` hold
///   only the prefix state (`drive_c`, `system.reg`, `user.reg`,
///   `BottleSettings.plist`). The probe resolves the shared binary and
///   pairs it with the most-recently-modified bottle as `WINEPREFIX`. If
///   no bottle exists, a `~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/default/`
///   path is passed and Whisky creates it on demand.
/// * The unverified `/usr/bin/open -a Whisky --args <exe>` fallback has
///   been removed. If neither the shared wine64 nor any other compat
///   layer is present, `resolveLaunch` throws
///   `.whiskyNotConfigured` (when Whisky.app is installed but the shared
///   wine64 is missing) or `.noCompatibilityLayerDetected`.
/// * GPTK's `wine64` lives under its Homebrew cellar (`.../game-porting-toolkit/.../bin/wine64`)
///   or under whatever prefix Apple's installer created. The probe walks
///   both Homebrew prefixes and records the first `wine64` that exists.
/// * Every layer contributes a `[String: String]` environment-variable
///   bundle that `launchGame` merges with the inherited process
///   environment before spawning. Whisky contributes `WINEPREFIX=<bottle>`.
///   GPTK contributes Metal/Rosetta knobs + a dedicated
///   `~/Library/Application Support/BFME Foundation/GPTK-Prefix/`.
///   Wine contributes a `~/Library/Application Support/BFME Foundation/Wine-Prefix/`.
///   CrossOver's bundled wine sets its own env; we contribute nothing.
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
    /// env-var plumbing, and the registry lookup can all be swapped out.
    /// A synthetic filesystem is expressed by overriding `fileExists` with
    /// a set of paths that the test wants to "exist".
    public struct Environment: Sendable {
        public var fileExists: @Sendable (String) -> Bool
        public var installPathForGame: @Sendable (BfmeGame) async -> String
        public var activeModPathForGame: @Sendable (BfmeGame) async -> String
        /// Extended signature (review-v2 #3): each compat layer contributes
        /// an environment-variable bundle that gets merged with the
        /// inherited process env. `runProcess` is responsible for merging.
        public var runProcess: @Sendable (_ launchPath: String, _ arguments: [String], _ currentDirectory: String?, _ environment: [String: String]) throws -> Int32
        /// Returns every entry in a directory (non-recursive). Used by the
        /// Whisky probe to walk the Bottles container. Defaults to
        /// `FileManager.contentsOfDirectory`; tests can substitute a canned
        /// listing.
        public var directoryContents: @Sendable (String) -> [String]
        /// Returns the last-modified timestamp for `path`. Used by the
        /// Whisky probe to pick the most recently-used bottle when multiple
        /// exist. Defaults to `FileManager.attributesOfItem(atPath:)`;
        /// tests can substitute a canned timestamp table.
        public var modificationDate: @Sendable (String) -> Date?
        /// Creates a directory (with intermediates). Used by `launchGame`
        /// to materialize the GPTK and Wine prefixes before the child
        /// process is spawned. Defaults to `FileManager.createDirectory`;
        /// tests can no-op it.
        public var createDirectory: @Sendable (String) -> Void
        /// Expands `~` to the user's home directory. Overridable so tests
        /// don't accidentally touch the tester's real home.
        public var homeDirectory: @Sendable () -> String
        /// Returns the current process environment the caller inherited.
        /// Overridable so tests can assert the exact merge behavior.
        public var processEnvironment: @Sendable () -> [String: String]

        public init(
            fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
            installPathForGame: @escaping @Sendable (BfmeGame) async -> String = { game in
                await BfmeRegistryManager.getKeyValue(game.rawValue, .installPath)
            },
            activeModPathForGame: @escaping @Sendable (BfmeGame) async -> String = { _ in "" },
            runProcess: @escaping @Sendable (String, [String], String?, [String: String]) throws -> Int32 = { try Environment.defaultRunProcess($0, $1, $2, $3) },
            directoryContents: @escaping @Sendable (String) -> [String] = { path in
                (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            },
            modificationDate: @escaping @Sendable (String) -> Date? = { path in
                (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            },
            createDirectory: @escaping @Sendable (String) -> Void = { path in
                try? FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: path),
                    withIntermediateDirectories: true
                )
            },
            homeDirectory: @escaping @Sendable () -> String = { FileManager.default.homeDirectoryForCurrentUser.path },
            processEnvironment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }
        ) {
            self.fileExists = fileExists
            self.installPathForGame = installPathForGame
            self.activeModPathForGame = activeModPathForGame
            self.runProcess = runProcess
            self.directoryContents = directoryContents
            self.modificationDate = modificationDate
            self.createDirectory = createDirectory
            self.homeDirectory = homeDirectory
            self.processEnvironment = processEnvironment
        }

        public static func defaultRunProcess(
            _ launchPath: String,
            _ arguments: [String],
            _ currentDirectory: String?,
            _ environment: [String: String]
        ) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            if let currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            }
            // Inherit the parent env, then merge per-layer overrides on top.
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
    }

    public enum LaunchError: Error, Equatable, CustomStringConvertible {
        case noCompatibilityLayerDetected
        case whiskyNotConfigured
        case gameNotInstalled(BfmeGame)
        case executableMissing(path: String)
        case compatRuntimeMissing(path: String)

        public var description: String {
            switch self {
            case .noCompatibilityLayerDetected:
                return "No Wine, CrossOver, Whisky, or Game Porting Toolkit install was detected. Install one of these to run BFME on macOS."
            case .whiskyNotConfigured:
                return "Whisky is installed but its shared wine64 runtime is missing. Open Whisky once so it downloads its Wine libraries, then try again."
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
        /// For every layer this is a wine/wine64 binary we actually located
        /// on disk. The `open -a Whisky --args` fallback from v1 has been
        /// removed: Whisky is driven through its shared wine64 + WINEPREFIX.
        public let runnerBinaryPath: String
        /// Whisky-only: the bottle prefix passed to wine64 through
        /// `WINEPREFIX=...`. Nil for the other three layers.
        public let whiskyBottlePrefix: String?

        public init(
            layer: CompatibilityLayer,
            runnerBinaryPath: String,
            whiskyBottlePrefix: String? = nil
        ) {
            self.layer = layer
            self.runnerBinaryPath = runnerBinaryPath
            self.whiskyBottlePrefix = whiskyBottlePrefix
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
    /// Shared wine64 locations Whisky 2.x uses for its bundled Wine install.
    /// The probe keeps the first match.
    static let whiskySharedWine64Candidates: [String] = [
        "~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64",
        "~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine64/bin/wine64"
    ]
    /// Root under which Whisky stores bottle prefix state (one directory per
    /// UUID). The wine binary does NOT live here.
    static let whiskyBottlesRootSuffix = "/Library/Containers/com.isaacmarovitz.Whisky/Bottles"
    static let whiskyDefaultBottleName = "default"

    /// Per-layer wine prefix roots for Wine / GPTK. Whisky uses its own
    /// bottle directory. CrossOver uses the prefix its bundled wine
    /// configures internally so we do not override it.
    static let gptkPrefixSuffix = "/Library/Application Support/BFME Foundation/GPTK-Prefix"
    static let winePrefixSuffix = "/Library/Application Support/BFME Foundation/Wine-Prefix"

    /// Resolves `(sharedWine64, bottlePrefix)` for the Whisky install, if
    /// any. `bottlePrefix` is the most-recently-modified bottle directory
    /// under `~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/` (or
    /// the first entry when no mtime is available). When no bottle exists
    /// the prefix points at a default location that Whisky creates on
    /// first run. Returns `nil` when the shared wine64 binary itself is
    /// missing.
    static func resolveWhiskyBottleRunner(environment: Environment) -> (sharedWine64: String, bottlePrefix: String)? {
        guard let sharedWine64 = firstExistingBinary(whiskySharedWine64Candidates, environment: environment) else {
            return nil
        }
        let home = environment.homeDirectory()
        let bottlesRoot = home + whiskyBottlesRootSuffix
        let entries = environment.directoryContents(bottlesRoot)
            .filter { !$0.hasPrefix(".") }
        let bottles: [(path: String, modified: Date?)] = entries.map { entry in
            let path = bottlesRoot + "/" + entry
            return (path, environment.modificationDate(path))
        }

        // Pick the most recently modified bottle. Ties + missing mtimes
        // fall through to the first entry the directory listing returned.
        let selected: String?
        if let withDates = bottles.compactMap({ pair in pair.modified.map { (pair.path, $0) } }).max(by: { $0.1 < $1.1 })?.0 {
            selected = withDates
        } else if let first = bottles.first?.path {
            selected = first
        } else {
            selected = nil
        }

        if let bottle = selected {
            return (sharedWine64, bottle)
        }
        // No existing bottle: point at the default Whisky will create on
        // demand the next time the user launches something. We deliberately
        // do NOT mkdir this path ourselves; Whisky owns the bottle schema.
        return (sharedWine64, bottlesRoot + "/" + whiskyDefaultBottleName)
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

        // Whisky: the shared wine64 binary lives under Application Support,
        // the bottle prefix under Containers. We only emit a Whisky layer
        // when the shared wine64 is present (v2 review fix #2: the
        // `open -a Whisky --args` fallback has been removed).
        if let (wine64, bottlePrefix) = resolveWhiskyBottleRunner(environment: environment) {
            layers.append(.init(layer: .whisky, runnerBinaryPath: wine64, whiskyBottlePrefix: bottlePrefix))
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
        /// The exact binary the OS will exec (wine / wine64).
        /// Threaded through from the probe so runner-command emission never
        /// hardcodes a path that the probe did not verify.
        public let runnerBinaryPath: String
        /// Whisky-only: the bottle prefix that should be forwarded through
        /// `WINEPREFIX`. Nil for other layers. GPTK/Wine prefixes live
        /// under Application Support/BFME Foundation and are materialized
        /// by `launchGame` before spawning.
        public let whiskyBottlePrefix: String?
        /// Per-layer environment-variable overrides. Callers merge this on
        /// top of the inherited process env. Built from
        /// `runnerEnvironment(for:environment:)` during `resolveLaunch` so
        /// tests can assert on it without running a process.
        public let environmentOverrides: [String: String]
    }

    /// Resolves the full launch command for a game: installed executable,
    /// working directory, `-mod` arguments (from `BfmeWorkshopManager.GetActiveModPath`
    /// in the C# version), the detected compatibility layer, and the
    /// per-layer env overrides. Throws if anything is missing.
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
        if layers.isEmpty {
            // Whisky.app may be installed but the shared wine64 missing.
            // Emit a more actionable error in that case so the user knows
            // to open Whisky once to trigger its Wine download.
            let home = environment.homeDirectory()
            let whiskyAppPath = "/Applications/Whisky.app"
            let bottlesRoot = home + whiskyBottlesRootSuffix
            let whiskyLooksPresent =
                environment.fileExists(whiskyAppPath) ||
                !environment.directoryContents(bottlesRoot).isEmpty
            if whiskyLooksPresent {
                throw LaunchError.whiskyNotConfigured
            }
            throw LaunchError.noCompatibilityLayerDetected
        }
        let detected = layers[0]

        var args: [String] = []
        let modPath = await environment.activeModPathForGame(game)
        if !modPath.isEmpty {
            args.append("-mod")
            args.append(modPath)
        }

        let env = runnerEnvironment(for: detected, environment: environment)

        return ResolvedLaunch(
            game: game,
            executablePath: executablePath,
            workingDirectory: installPath,
            arguments: args,
            compatibilityLayer: detected.layer,
            runnerBinaryPath: detected.runnerBinaryPath,
            whiskyBottlePrefix: detected.whiskyBottlePrefix,
            environmentOverrides: env
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
        // Materialize any prefix directory the layer expects before handing
        // off to wine. Whisky owns its own bottle schema so we skip that.
        if let prefix = resolved.environmentOverrides["WINEPREFIX"],
           resolved.compatibilityLayer != .whisky {
            environment.createDirectory(prefix)
        }
        _ = try environment.runProcess(runnerPath, runnerArgs, resolved.workingDirectory, resolved.environmentOverrides)
    }

    /// Returns the (binary, argv) needed to invoke `executablePath` through
    /// `resolved.compatibilityLayer`. Public so tests can assert on the
    /// command shape without actually spawning a process.
    public static func runnerCommand(for resolved: ResolvedLaunch) -> (String, [String]) {
        switch resolved.compatibilityLayer {
        case .whisky, .crossover, .wine, .gamePortingToolkit:
            return (resolved.runnerBinaryPath, [resolved.executablePath] + resolved.arguments)
        }
    }

    /// Returns the per-layer environment-variable overrides that should be
    /// merged on top of the inherited process env before spawning. Public
    /// so tests can assert the shape without running a process.
    public static func runnerEnvironment(
        for detected: DetectedLayer,
        environment: Environment
    ) -> [String: String] {
        let home = environment.homeDirectory()
        switch detected.layer {
        case .whisky:
            // Whisky: forward the bottle prefix so the shared wine64 runs
            // against the correct drive_c / registry hives. Bottle layout
            // is Whisky's concern; we never mkdir it ourselves.
            if let prefix = detected.whiskyBottlePrefix {
                return ["WINEPREFIX": prefix]
            }
            return [:]
        case .crossover:
            // CrossOver's bundled wine sets its own env rig internally
            // (CX_ROOT, WINEPREFIX, CX_BOTTLE, ...). Overriding any of
            // these through `--args` would confuse its launcher, so we
            // leave it alone.
            return [:]
        case .gamePortingToolkit:
            return [
                "WINEPREFIX": home + gptkPrefixSuffix,
                "MTL_HUD_ENABLED": "0",
                "MTL_DEBUG_LAYER": "0",
                "WINEESYNC": "1",
                "ROSETTA_ADVERTISE_AVX": "1"
            ]
        case .wine:
            return [
                "WINEPREFIX": home + winePrefixSuffix
            ]
        }
    }

    // MARK: - Helpers

    private static func joinPath(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if a.hasSuffix("/") || a.hasSuffix(#"\"#) { return a + b }
        return a + "/" + b
    }
}
