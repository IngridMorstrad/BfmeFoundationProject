import Foundation
import BfmeKit

/// Port of `ArenaProcessHelper.cs`. The Windows original does three things:
///   1. Spawns `BfmeFoundationProject_OnlineArena.exe` via `Process.Start`.
///   2. Opens a named pipe and hands the pipe name to the child so it can
///      stream layout hints back.
///   3. Reads the child's top-level HWND off the pipe and reparents that
///      HWND into the launcher window using Win32 `SetParent`.
///
/// Step (3) is explicitly Windows-only — there is no cross-platform way to
/// embed a Wine-hosted window into a native NSWindow, and the review's
/// guidance was to leave window embedding as a documented TODO. Steps (1)
/// and (2) port cleanly: macOS has `Process` for spawning and `FileHandle`
/// pipes or named Unix domain sockets for IPC. We keep the process-spawn
/// piece here and stub the window-embed side until a future iteration can
/// experiment with `CGSSetWindowTransform`-style tricks on a real Mac.
///
/// `Win32Helper` (review bullet #13 last item) was intentionally dropped:
/// it was a grab-bag of P/Invoke declarations (`SetParent`, `MoveWindow`,
/// `SendMessage`) that have no portable analog. Callers on macOS must not
/// attempt window reparenting.
public enum ArenaProcessHelper {
    /// Runtime knobs set by the caller. The launcher populates
    /// `runnerResolver` with a closure that returns the (binary, arg
    /// prefix) for the active compatibility layer — this indirection
    /// keeps `BfmeOnlineKit` decoupled from `BfmeLauncherApp`'s
    /// `BfmeLaunchManager` while still letting the arena exe go through
    /// the same Wine/CrossOver/Whisky resolver.
    public struct Configuration: Sendable {
        /// Returns `(launchPath, argPrefix)` given the game exe path. The
        /// prefix is typically `[exePath]` so the exe is handed to wine
        /// as its first argument. When no compat layer is available the
        /// resolver returns `nil` and `launch` throws.
        public var runnerResolver: @Sendable (String) async -> (String, [String])?

        public init(runnerResolver: @escaping @Sendable (String) async -> (String, [String])?) {
            self.runnerResolver = runnerResolver
        }
    }

    public enum ArenaError: Error, CustomStringConvertible {
        case notInstalled
        case noCompatibilityLayer
        case spawnFailed(String)

        public var description: String {
            switch self {
            case .notInstalled: return "Arena binary is not installed."
            case .noCompatibilityLayer: return "No Wine/CrossOver/Whisky runtime is available to host the arena exe."
            case .spawnFailed(let msg): return "Arena spawn failed: \(msg)"
            }
        }
    }

    /// The running arena process, if any. Exposed for tests.
    nonisolated(unsafe) private static var running: Process?
    private static let lock = NSLock()

    private static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    /// Launches the arena binary through the supplied runner resolver. The
    /// arguments match the Windows invocation (see `ArenaProcessHelper.cs`):
    /// `--embedded <token> <branch> --new --corner-radius <r> --scale <json> --pipe-name <uuid>`.
    /// Unlike Windows, we do not attempt to reparent the child window — that
    /// step is documented as a macOS TODO (see doc comment above).
    @discardableResult
    public static func launch(
        accessToken: String,
        updateBranch: String,
        cornerRadius: Double,
        scaleJSON: String,
        pipeName: String = UUID().uuidString,
        configuration: Configuration
    ) async throws -> Process {
        guard ArenaDataHelper.isInstalled else { throw ArenaError.notInstalled }

        FirewallHelper.addFirewallRule(
            name: "Bfme Foundation Project - Online Menu",
            program: ArenaDataHelper.arenaExecutablePath
        )

        let exePath = ArenaDataHelper.arenaExecutablePath
        guard let (runner, argPrefix) = await configuration.runnerResolver(exePath) else {
            throw ArenaError.noCompatibilityLayer
        }

        let arenaArgs = [
            "--embedded", accessToken,
            updateBranch,
            "--new",
            "--corner-radius", String(cornerRadius),
            "--scale", scaleJSON,
            "--pipe-name", pipeName
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: runner)
        process.arguments = argPrefix + arenaArgs
        process.currentDirectoryURL = URL(fileURLWithPath: ArenaDataHelper.globalInstallPath)
        do {
            try process.run()
        } catch {
            throw ArenaError.spawnFailed(String(describing: error))
        }
        withLock { running = process }
        return process
    }

    /// Signals any previously-spawned arena process to terminate, then
    /// waits. On macOS we send `SIGTERM` rather than a Win32 `WM_CLOSE`;
    /// the wine-hosted child translates the signal internally.
    public static func unload() async {
        let p: Process? = withLock {
            let existing = running
            running = nil
            return existing
        }
        guard let process = p else { return }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
    }

    /// True while an arena process is hosted. Exposed for tests.
    public static var isRunning: Bool {
        withLock { running?.isRunning ?? false }
    }
}
