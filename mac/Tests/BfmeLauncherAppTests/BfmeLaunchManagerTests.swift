import XCTest
@testable import BfmeLauncherApp
import BfmeKitCore

final class BfmeLaunchManagerTests: XCTestCase {
    // MARK: - Detection

    func testNoCompatibilityLayerReturnsEmpty() {
        let env = BfmeLaunchManager.Environment(
            fileExists: { _ in false },
            installPathForGame: { _ in "/tmp/bfme" },
            activeModPathForGame: { _ in "" },
            runProcess: { _, _, _ in XCTFail("should not run"); return 0 }
        )
        XCTAssertTrue(BfmeLaunchManager.detectCompatibilityLayers(environment: env).isEmpty)
    }

    /// When Whisky is installed and the user has at least one bottle, the
    /// probe resolves the active bottle's wine64 binary.
    func testDetectsWhiskyViaBottleWine64() throws {
        let home = "/Users/tester"
        let bottleRunner = home + "/Library/Containers/com.isaacmarovitz.Whisky/Bottles/ABCD-1234/wine/bin/wine64"
        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == bottleRunner },
            directoryContents: { path in
                if path == home + "/Library/Containers/com.isaacmarovitz.Whisky/Bottles" {
                    return ["ABCD-1234"]
                }
                return []
            },
            homeDirectory: { home }
        )
        let layers = BfmeLaunchManager.detectCompatibilityLayers(environment: env)
        XCTAssertEqual(layers.map(\.layer), [.whisky])
        XCTAssertEqual(layers.first?.runnerBinaryPath, bottleRunner)
        XCTAssertEqual(layers.first?.usesWhiskyAppFallback, false)
    }

    /// When Whisky.app exists but no bottle is set up, the probe falls back
    /// to `open -a Whisky`.
    func testDetectsWhiskyViaOpenAppFallback() throws {
        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == "/Applications/Whisky.app" },
            directoryContents: { _ in [] },
            homeDirectory: { "/Users/tester" }
        )
        let layers = BfmeLaunchManager.detectCompatibilityLayers(environment: env)
        XCTAssertEqual(layers.map(\.layer), [.whisky])
        XCTAssertEqual(layers.first?.runnerBinaryPath, "/usr/bin/open")
        XCTAssertEqual(layers.first?.usesWhiskyAppFallback, true)
    }

    /// The Apple Silicon Wine path (`/opt/homebrew/bin/wine`) is now covered
    /// by the probe and threaded through `ResolvedLaunch.runnerBinaryPath`.
    func testDetectsAppleSiliconHomebrewWine() {
        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == "/opt/homebrew/bin/wine" },
            directoryContents: { _ in [] },
            homeDirectory: { "/Users/tester" }
        )
        let layers = BfmeLaunchManager.detectCompatibilityLayers(environment: env)
        XCTAssertEqual(layers.map(\.layer), [.wine])
        XCTAssertEqual(layers.first?.runnerBinaryPath, "/opt/homebrew/bin/wine")
    }

    /// GPTK wine64 lives under its Homebrew cellar, not at
    /// `/usr/local/bin/wine64` like the old code assumed.
    func testDetectsGptkWine64InHomebrewCellar() {
        let path = "/opt/homebrew/opt/game-porting-toolkit/bin/wine64"
        let env = BfmeLaunchManager.Environment(
            fileExists: { p in p == path },
            directoryContents: { _ in [] },
            homeDirectory: { "/Users/tester" }
        )
        let layers = BfmeLaunchManager.detectCompatibilityLayers(environment: env)
        XCTAssertEqual(layers.map(\.layer), [.gamePortingToolkit])
        XCTAssertEqual(layers.first?.runnerBinaryPath, path)
    }

    // MARK: - Per-layer runner command assertions

    /// Each compatibility layer below is wired to a matched runner path the
    /// probe actually found. The runner command must invoke exactly that
    /// binary, with argv composed of (exe, -mod, modPath). This is the
    /// coverage the review asked for.
    func testRunnerCommandForWhiskyBottlePassesExeThroughWine64() throws {
        let resolved = BfmeLaunchManager.ResolvedLaunch(
            game: .bfme1,
            executablePath: "/Users/tester/BFME/lotrbfme.exe",
            workingDirectory: "/Users/tester/BFME",
            arguments: ["-mod", "/Users/tester/BFME/mod"],
            compatibilityLayer: .whisky,
            runnerBinaryPath: "/Users/tester/Library/Containers/com.isaacmarovitz.Whisky/Bottles/ABCD/wine/bin/wine64",
            usesWhiskyAppFallback: false
        )
        let (runner, args) = BfmeLaunchManager.runnerCommand(for: resolved)
        XCTAssertEqual(runner, resolved.runnerBinaryPath)
        XCTAssertEqual(args, [
            "/Users/tester/BFME/lotrbfme.exe",
            "-mod",
            "/Users/tester/BFME/mod"
        ])
    }

    func testRunnerCommandForWhiskyAppFallbackUsesOpenArgs() throws {
        let resolved = BfmeLaunchManager.ResolvedLaunch(
            game: .bfme2,
            executablePath: "/tmp/bfme2.exe",
            workingDirectory: "/tmp",
            arguments: [],
            compatibilityLayer: .whisky,
            runnerBinaryPath: "/usr/bin/open",
            usesWhiskyAppFallback: true
        )
        let (runner, args) = BfmeLaunchManager.runnerCommand(for: resolved)
        XCTAssertEqual(runner, "/usr/bin/open")
        XCTAssertEqual(args, ["-a", "Whisky", "--args", "/tmp/bfme2.exe"])
    }

    func testRunnerCommandForCrossOverInvokesBundledWine() throws {
        let resolved = BfmeLaunchManager.ResolvedLaunch(
            game: .bfme1,
            executablePath: "/Users/t/BFME/lotrbfme.exe",
            workingDirectory: "/Users/t/BFME",
            arguments: [],
            compatibilityLayer: .crossover,
            runnerBinaryPath: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine",
            usesWhiskyAppFallback: false
        )
        let (runner, args) = BfmeLaunchManager.runnerCommand(for: resolved)
        XCTAssertEqual(runner, "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine")
        XCTAssertEqual(args, ["/Users/t/BFME/lotrbfme.exe"])
    }

    func testRunnerCommandForWineUsesProbeMatchedPath() throws {
        // The probe matched Apple Silicon Homebrew; the runner must not
        // silently rewrite that path to Intel's `/usr/local`.
        let resolved = BfmeLaunchManager.ResolvedLaunch(
            game: .rotwk,
            executablePath: "/x/lotrbfme2ep1.exe",
            workingDirectory: "/x",
            arguments: ["-mod", "/x/mod"],
            compatibilityLayer: .wine,
            runnerBinaryPath: "/opt/homebrew/bin/wine",
            usesWhiskyAppFallback: false
        )
        let (runner, args) = BfmeLaunchManager.runnerCommand(for: resolved)
        XCTAssertEqual(runner, "/opt/homebrew/bin/wine")
        XCTAssertEqual(args, ["/x/lotrbfme2ep1.exe", "-mod", "/x/mod"])
    }

    func testRunnerCommandForGPTKUsesProbeMatchedPath() throws {
        let resolved = BfmeLaunchManager.ResolvedLaunch(
            game: .bfme2,
            executablePath: "/x/lotrbfme2.exe",
            workingDirectory: "/x",
            arguments: [],
            compatibilityLayer: .gamePortingToolkit,
            runnerBinaryPath: "/opt/homebrew/opt/game-porting-toolkit/bin/wine64",
            usesWhiskyAppFallback: false
        )
        let (runner, args) = BfmeLaunchManager.runnerCommand(for: resolved)
        XCTAssertEqual(runner, "/opt/homebrew/opt/game-porting-toolkit/bin/wine64")
        XCTAssertEqual(args, ["/x/lotrbfme2.exe"])
    }

    // MARK: - resolveLaunch end-to-end

    func testResolveLaunchComposesWhiskyBottleCommand() async throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let exeURL = tempRoot.appendingPathComponent("lotrbfme.exe")
        try Data([0x4D, 0x5A]).write(to: exeURL) // "MZ" DOS stub

        let home = "/Users/tester"
        let bottleRunner = home + "/Library/Containers/com.isaacmarovitz.Whisky/Bottles/B-1/wine/bin/wine64"
        let env = BfmeLaunchManager.Environment(
            fileExists: { path in
                if path == exeURL.path { return true }
                if path == bottleRunner { return true }
                return false
            },
            installPathForGame: { _ in tempRoot.path },
            activeModPathForGame: { _ in "" },
            runProcess: { _, _, _ in 0 },
            directoryContents: { path in
                if path == home + "/Library/Containers/com.isaacmarovitz.Whisky/Bottles" {
                    return ["B-1"]
                }
                return []
            },
            homeDirectory: { home }
        )

        let resolved = try await BfmeLaunchManager.resolveLaunch(for: .bfme1, environment: env)
        XCTAssertEqual(resolved.game, .bfme1)
        XCTAssertEqual(resolved.compatibilityLayer, .whisky)
        XCTAssertEqual(resolved.runnerBinaryPath, bottleRunner)
        XCTAssertEqual(resolved.executablePath, exeURL.path)
        XCTAssertEqual(resolved.workingDirectory, tempRoot.path)
        XCTAssertTrue(resolved.arguments.isEmpty)

        let (runner, args) = BfmeLaunchManager.runnerCommand(for: resolved)
        XCTAssertEqual(runner, bottleRunner)
        XCTAssertEqual(args, [exeURL.path])
    }

    func testResolveLaunchWithActiveModAddsModArgument() async throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let exeURL = tempRoot.appendingPathComponent("lotrbfme2.exe")
        try Data([0x4D, 0x5A]).write(to: exeURL)

        let modPath = "/Users/example/.wine/drive_c/mod"
        let crossoverPath = "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"
        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == exeURL.path || path == crossoverPath },
            installPathForGame: { _ in tempRoot.path },
            activeModPathForGame: { _ in modPath },
            runProcess: { _, _, _ in 0 },
            directoryContents: { _ in [] },
            homeDirectory: { "/Users/tester" }
        )

        let resolved = try await BfmeLaunchManager.resolveLaunch(for: .bfme2, environment: env)
        XCTAssertEqual(resolved.compatibilityLayer, .crossover)
        XCTAssertEqual(resolved.runnerBinaryPath, crossoverPath)
        XCTAssertEqual(resolved.arguments, ["-mod", modPath])
    }

    func testResolveLaunchFailsWhenNoCompatibilityLayer() async throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let exeURL = tempRoot.appendingPathComponent("lotrbfme.exe")
        try Data([0x4D, 0x5A]).write(to: exeURL)

        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == exeURL.path },
            installPathForGame: { _ in tempRoot.path },
            activeModPathForGame: { _ in "" },
            runProcess: { _, _, _ in 0 },
            directoryContents: { _ in [] },
            homeDirectory: { "/Users/tester" }
        )

        do {
            _ = try await BfmeLaunchManager.resolveLaunch(for: .bfme1, environment: env)
            XCTFail("expected noCompatibilityLayerDetected")
        } catch let error as BfmeLaunchManager.LaunchError {
            XCTAssertEqual(error, .noCompatibilityLayerDetected)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testResolveLaunchFailsWhenExecutableMissing() async throws {
        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == "/Applications/Whisky.app" },
            installPathForGame: { _ in "/nonexistent/install" },
            activeModPathForGame: { _ in "" },
            runProcess: { _, _, _ in 0 },
            directoryContents: { _ in [] },
            homeDirectory: { "/Users/tester" }
        )
        do {
            _ = try await BfmeLaunchManager.resolveLaunch(for: .bfme1, environment: env)
            XCTFail("expected executableMissing")
        } catch let error as BfmeLaunchManager.LaunchError {
            if case .executableMissing = error { return }
            XCTFail("unexpected error: \(error)")
        }
    }

    func testResolveLaunchFailsWhenGameNotInstalled() async throws {
        let env = BfmeLaunchManager.Environment(
            fileExists: { _ in true },
            installPathForGame: { _ in "" },
            activeModPathForGame: { _ in "" },
            runProcess: { _, _, _ in 0 },
            directoryContents: { _ in [] },
            homeDirectory: { "/Users/tester" }
        )
        do {
            _ = try await BfmeLaunchManager.resolveLaunch(for: .bfme1, environment: env)
            XCTFail("expected gameNotInstalled")
        } catch let error as BfmeLaunchManager.LaunchError {
            if case .gameNotInstalled = error { return }
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeTempDir(file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bfme-launch-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
