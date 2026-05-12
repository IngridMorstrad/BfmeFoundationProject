import Foundation
import BfmeKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
/// and (2) port cleanly: macOS has `Process` for spawning and POSIX FIFOs
/// for IPC. We create the FIFO BEFORE `Process.run` (review-v2 #4) so the
/// child has somewhere to connect when it starts up.
///
/// The read side of the FIFO is the CALLER's responsibility: `launch`
/// returns the FIFO path through `LaunchResult.pipePath` and leaves it
/// dangling after the child exits. Higher layers that want to consume
/// layout hints open the FIFO themselves (`FileHandle(forReadingAtPath:)`)
/// and drive the I/O on their preferred queue. We wire a full
/// Network.framework `NWListener` only when a consumer asks for it; for
/// the current iteration a FIFO is sufficient to honor the child's argv
/// contract and unblock `Process.run`.
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
        case pipeCreateFailed(String)

        public var description: String {
            switch self {
            case .notInstalled: return "Arena binary is not installed."
            case .noCompatibilityLayer: return "No Wine/CrossOver/Whisky runtime is available to host the arena exe."
            case .spawnFailed(let msg): return "Arena spawn failed: \(msg)"
            case .pipeCreateFailed(let msg): return "Arena pipe create failed: \(msg)"
            }
        }
    }

    /// Return value for `launch`. Exposes both the spawned `Process` and
    /// the filesystem path of the FIFO so callers can open the read side
    /// at their leisure.
    public struct LaunchResult: @unchecked Sendable {
        public let process: Process
        public let pipePath: String
    }

    /// Creates a POSIX FIFO at `/tmp/bfme-arena-<uuid>.sock` (or a
    /// caller-supplied directory). Returns the absolute path on success.
    /// Public so tests can verify the endpoint exists before any process
    /// is spawned.
    public static func createPipeEndpoint(
        uuid: String = UUID().uuidString,
        directory: String = NSTemporaryDirectory()
    ) throws -> String {
        let normalizedDir = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        let path = "\(normalizedDir)/bfme-arena-\(uuid).sock"
        // If something stale exists, remove it. The FIFO lives only for
        // the lifetime of the arena process.
        unlink(path)
        let result = path.withCString { cString in
            mkfifo(cString, 0o600)
        }
        if result != 0 {
            let code = errno
            let message = String(cString: strerror(code))
            throw ArenaError.pipeCreateFailed("mkfifo(\(path)) failed: \(message)")
        }
        return path
    }

    /// The running arena process, if any. Exposed for tests.
    nonisolated(unsafe) private static var running: Process?
    nonisolated(unsafe) private static var runningPipePath: String?
    private static let lock = NSLock()

    private static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    /// Launches the arena binary through the supplied runner resolver. The
    /// arguments match the Windows invocation (see `ArenaProcessHelper.cs`):
    /// `--embedded <token> <branch> --new --corner-radius <r> --scale <json> --pipe-name <path>`.
    /// The FIFO at `--pipe-name` is created BEFORE `Process.run` so the
    /// child never races a non-existent endpoint. Unlike Windows, we do not
    /// attempt to reparent the child window — that step is documented as a
    /// macOS TODO (see doc comment above).
    @discardableResult
    public static func launch(
        accessToken: String,
        updateBranch: String,
        cornerRadius: Double,
        scaleJSON: String,
        pipeUUID: String = UUID().uuidString,
        configuration: Configuration
    ) async throws -> LaunchResult {
        guard ArenaDataHelper.isInstalled else { throw ArenaError.notInstalled }

        // Create the IPC endpoint FIRST. Review-v2 #4: the previous port
        // forwarded `--pipe-name` on argv but never created anything at
        // that path, so the child would hang on connect.
        let pipePath = try createPipeEndpoint(uuid: pipeUUID)

        FirewallHelper.addFirewallRule(
            name: "Bfme Foundation Project - Online Menu",
            program: ArenaDataHelper.arenaExecutablePath
        )

        let exePath = ArenaDataHelper.arenaExecutablePath
        guard let (runner, argPrefix) = await configuration.runnerResolver(exePath) else {
            unlink(pipePath)
            throw ArenaError.noCompatibilityLayer
        }

        let arenaArgs = [
            "--embedded", accessToken,
            updateBranch,
            "--new",
            "--corner-radius", String(cornerRadius),
            "--scale", scaleJSON,
            "--pipe-name", pipePath
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: runner)
        process.arguments = argPrefix + arenaArgs
        process.currentDirectoryURL = URL(fileURLWithPath: ArenaDataHelper.globalInstallPath)
        do {
            try process.run()
        } catch {
            unlink(pipePath)
            throw ArenaError.spawnFailed(String(describing: error))
        }
        withLock {
            running = process
            runningPipePath = pipePath
        }
        return LaunchResult(process: process, pipePath: pipePath)
    }

    /// Signals any previously-spawned arena process to terminate, then
    /// waits. On macOS we send `SIGTERM` rather than a Win32 `WM_CLOSE`;
    /// the wine-hosted child translates the signal internally. Also
    /// unlinks the FIFO so `/tmp` does not accumulate stale endpoints.
    public static func unload() async {
        let snapshot: (Process?, String?) = withLock {
            let existing = running
            let pipe = runningPipePath
            running = nil
            runningPipePath = nil
            return (existing, pipe)
        }
        if let process = snapshot.0 {
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
        }
        if let pipe = snapshot.1 {
            unlink(pipe)
        }
    }

    /// True while an arena process is hosted. Exposed for tests.
    public static var isRunning: Bool {
        withLock { running?.isRunning ?? false }
    }
}
