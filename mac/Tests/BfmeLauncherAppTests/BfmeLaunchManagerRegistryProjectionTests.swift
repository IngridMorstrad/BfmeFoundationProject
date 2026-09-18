import XCTest
import BfmeKitCore
import BfmeWineBridge
@testable import BfmeLauncherApp

/// Covers the step that writes launcher state into the Wine prefix before the
/// game starts. Without it the game reads an empty `InstallPath` from the
/// prefix registry and reports itself as not installed.
final class BfmeLaunchManagerRegistryProjectionTests: XCTestCase {
    private let installPath = "/Users/tester/Games/BFME2"

    /// Environment with a synthetic filesystem where Homebrew Wine and the game
    /// executable both exist.
    private func makeEnvironment(
        onProject: (@Sendable (BfmeGameRegistryState, WineRuntime) throws -> Void)? = nil,
        onRun: (@Sendable () -> Void)? = nil
    ) -> BfmeLaunchManager.Environment {
        let exePath = installPath + "/lotrbfme2.exe"
        let present: Set<String> = ["/opt/homebrew/bin/wine64", exePath]

        return BfmeLaunchManager.Environment(
            fileExists: { present.contains($0) },
            installPathForGame: { _ in self.installPath },
            activeModPathForGame: { _ in "" },
            runProcess: { _, _, _, _ in
                onRun?()
                return 0
            },
            directoryContents: { _ in [] },
            modificationDate: { _ in nil },
            createDirectory: { _ in },
            homeDirectory: { "/Users/tester" },
            processEnvironment: { [:] },
            registryStateForGame: { game, path in
                BfmeGameRegistryState(
                    game: game.rawValue,
                    installPathUnix: path,
                    language: "English",
                    serialKey: "ABCDEFGHIJKLMNOPQRST"
                )
            },
            projectRegistry: onProject ?? { _, _ in }
        )
    }

    func testLaunchProjectsRegistryStateBeforeStartingTheGame() async throws {
        let order = Locked<[String]>([])

        let environment = makeEnvironment(
            onProject: { _, _ in order.mutate { $0.append("project") } },
            onRun: { order.mutate { $0.append("run") } }
        )

        try await BfmeLaunchManager.launchGame(.bfme2, environment: environment)

        // The registry must be written before the game reads it.
        XCTAssertEqual(order.value, ["project", "run"])
    }

    func testProjectionReceivesTheInstallPathAndResolvedPrefix() async throws {
        let captured = Locked<(BfmeGameRegistryState, WineRuntime)?>(nil)

        let environment = makeEnvironment(onProject: { state, runtime in
            captured.mutate { $0 = (state, runtime) }
        })

        try await BfmeLaunchManager.launchGame(.bfme2, environment: environment)

        let (state, runtime) = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.game, BfmeGame.bfme2.rawValue)
        // A POSIX path here is correct: translation to a Windows path happens
        // inside the bridge, which is the only place that can call winepath.
        XCTAssertEqual(state.installPathUnix, installPath)
        XCTAssertEqual(state.language, "English")
        XCTAssertEqual(runtime.binaryPath, "/opt/homebrew/bin/wine64")
        XCTAssertEqual(
            runtime.prefixPath,
            "/Users/tester/Library/Application Support/BFME Foundation/Wine-Prefix"
        )
    }

    func testLaunchStillProceedsWhenProjectionFails() async throws {
        let ran = Locked(false)

        let environment = makeEnvironment(
            onProject: { _, _ in throw WineBridgeError.emptyPathTranslation(input: "/x") },
            onRun: { ran.mutate { $0 = true } }
        )

        // A prefix may already hold correct registry state, so a projection
        // failure must not block the launch.
        try await BfmeLaunchManager.launchGame(.bfme2, environment: environment)

        XCTAssertTrue(ran.value)
    }

    func testProjectionIsSkippedWhenThereIsNoStateToWrite() async throws {
        let projected = Locked(false)
        var environment = makeEnvironment(onProject: { _, _ in projected.mutate { $0 = true } })
        environment.registryStateForGame = { _, _ in nil }

        try await BfmeLaunchManager.launchGame(.bfme2, environment: environment)

        XCTAssertFalse(projected.value)
    }
}

/// Minimal mutable box so the `@Sendable` closures above can record calls.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&storage)
    }
}
