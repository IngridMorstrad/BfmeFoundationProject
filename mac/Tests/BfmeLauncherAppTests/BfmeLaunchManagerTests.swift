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
            runProcess: { _, _, _, _ in XCTFail("should not run"); return 0 }
        )
        XCTAssertTrue(BfmeLaunchManager.detectCompatibilityLayers(environment: env).isEmpty)
    }

    /// Whisky 2.x keeps wine64 shared under Application Support and the
    /// bottle prefix under Containers. The probe returns both as a pair.
    func testDetectsWhiskyViaSharedWine64AndMostRecentBottle() throws {
        let home = "/Users/tester"
        let sharedWine64 = home + "/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64"
        let bottlesRoot = home + "/Library/Containers/com.isaacmarovitz.Whisky/Bottles"
        let older = bottlesRoot + "/OLD"
        let newer = bottlesRoot + "/NEW"

        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == sharedWine64 },
            directoryContents: { path in
                if path == bottlesRoot { return ["OLD", "NEW"] }
                return []
            },
            modificationDate: { path in
                if path == older { return Date(timeIntervalSince1970: 1000) }
                if path == newer { return Date(timeIntervalSince1970: 2000) }
                return nil
            },
            homeDirectory: { home }
        )
        let layers = BfmeLaunchManager.detectCompatibilityLayers(environment: env)
        XCTAssertEqual(layers.map(\.layer), [.whisky])
        XCTAssertEqual(layers.first?.runnerBinaryPath, sharedWine64)
        XCTAssertEqual(layers.first?.whiskyBottlePrefix, newer)
    }

    /// No bottles yet: the probe emits the default bottle path so Whisky
    /// can create it on demand when wine64 runs.
    func testDetectsWhiskyDefaultBottleWhenNoneExist() throws {
        let home = "/Users/tester"
        let sharedWine64 = home + "/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64"
        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == sharedWine64 },
            directoryContents: { _ in [] },
            modificationDate: { _ in nil },
            homeDirectory: { home }
        )
        let layers = BfmeLaunchManager.detectCompatibilityLayers(environment: env)
        XCTAssertEqual(layers.map(\.layer), [.whisky])
        XCTAssertEqual(layers.first?.runnerBinaryPath, sharedWine64)
        XCTAssertEqual(
            layers.first?.whiskyBottlePrefix,
            home + "/Library/Containers/com.isaacmarovitz.Whisky/Bottles/default"
        )
    }

    /// When the shared wine64 is missing the probe does NOT fall back to
    /// `open -a Whisky`. The v2 review removed that unverified path.
    func testWhiskyAppAloneDoesNotProduceALayer() throws {
        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == "/Applications/Whisky.app" },
            directoryContents: { _ in [] },
            modificationDate: { _ in nil },
            homeDirectory: { "/Users/tester" }
        )
        let layers = BfmeLaunchManager.detectCompatibilityLayers(environment: env)
        XCTAssertTrue(layers.isEmpty)
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
    /// binary, with argv composed of (exe, -mod, modPath). The env-var
    /// dictionary returned by `runnerEnvironment` is asserted separately.
    func testRunnerCommandForWhiskyInvokesSharedWine64WithExePlusArgs() throws {
        let resolved = BfmeLaunchManager.ResolvedLaunch(
            game: .bfme1,
            executablePath: "/Users/tester/BFME/lotrbfme.exe",
            workingDirectory: "/Users/tester/BFME",
            arguments: ["-mod", "/Users/tester/BFME/mod"],
            compatibilityLayer: .whisky,
            runnerBinaryPath: "/Users/tester/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64",
            whiskyBottlePrefix: "/Users/tester/Library/Containers/com.isaacmarovitz.Whisky/Bottles/ABCD",
            environmentOverrides: [:]
        )
        let (runner, args) = BfmeLaunchManager.runnerCommand(for: resolved)
        XCTAssertEqual(runner, resolved.runnerBinaryPath)
        XCTAssertEqual(args, [
            "/Users/tester/BFME/lotrbfme.exe",
            "-mod",
            "/Users/tester/BFME/mod"
        ])
    }

    func testRunnerCommandForCrossOverInvokesBundledWine() throws {
        let resolved = BfmeLaunchManager.ResolvedLaunch(
            game: .bfme1,
            executablePath: "/Users/t/BFME/lotrbfme.exe",
            workingDirectory: "/Users/t/BFME",
            arguments: [],
            compatibilityLayer: .crossover,
            runnerBinaryPath: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine",
            whiskyBottlePrefix: nil,
            environmentOverrides: [:]
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
            whiskyBottlePrefix: nil,
            environmentOverrides: [:]
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
            whiskyBottlePrefix: nil,
            environmentOverrides: [:]
        )
        let (runner, args) = BfmeLaunchManager.runnerCommand(for: resolved)
        XCTAssertEqual(runner, "/opt/homebrew/opt/game-porting-toolkit/bin/wine64")
        XCTAssertEqual(args, ["/x/lotrbfme2.exe"])
    }

    // MARK: - Per-layer environment-variable plumbing (v2 #3)

    func testRunnerEnvironmentForWhiskySetsWineprefixToBottle() {
        let env = BfmeLaunchManager.Environment(homeDirectory: { "/Users/tester" })
        let detected = BfmeLaunchManager.DetectedLayer(
            layer: .whisky,
            runnerBinaryPath: "/Users/tester/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64",
            whiskyBottlePrefix: "/Users/tester/Library/Containers/com.isaacmarovitz.Whisky/Bottles/ABCD"
        )
        let overrides = BfmeLaunchManager.runnerEnvironment(for: detected, environment: env)
        XCTAssertEqual(overrides, [
            "WINEPREFIX": "/Users/tester/Library/Containers/com.isaacmarovitz.Whisky/Bottles/ABCD"
        ])
    }

    func testRunnerEnvironmentForCrossOverIsEmpty() {
        let env = BfmeLaunchManager.Environment(homeDirectory: { "/Users/tester" })
        let detected = BfmeLaunchManager.DetectedLayer(
            layer: .crossover,
            runnerBinaryPath: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"
        )
        let overrides = BfmeLaunchManager.runnerEnvironment(for: detected, environment: env)
        XCTAssertTrue(overrides.isEmpty)
    }

    func testRunnerEnvironmentForGPTKSetsMetalAndRosettaKnobs() {
        let env = BfmeLaunchManager.Environment(homeDirectory: { "/Users/tester" })
        let detected = BfmeLaunchManager.DetectedLayer(
            layer: .gamePortingToolkit,
            runnerBinaryPath: "/opt/homebrew/opt/game-porting-toolkit/bin/wine64"
        )
        let overrides = BfmeLaunchManager.runnerEnvironment(for: detected, environment: env)
        XCTAssertEqual(overrides["MTL_HUD_ENABLED"], "0")
        XCTAssertEqual(overrides["MTL_DEBUG_LAYER"], "0")
        XCTAssertEqual(overrides["WINEESYNC"], "1")
        XCTAssertEqual(overrides["ROSETTA_ADVERTISE_AVX"], "1")
        XCTAssertEqual(
            overrides["WINEPREFIX"],
            "/Users/tester/Library/Application Support/BFME Foundation/GPTK-Prefix"
        )
    }

    func testRunnerEnvironmentForWineSetsBfmeFoundationPrefix() {
        let env = BfmeLaunchManager.Environment(homeDirectory: { "/Users/tester" })
        let detected = BfmeLaunchManager.DetectedLayer(
            layer: .wine,
            runnerBinaryPath: "/opt/homebrew/bin/wine"
        )
        let overrides = BfmeLaunchManager.runnerEnvironment(for: detected, environment: env)
        XCTAssertEqual(overrides, [
            "WINEPREFIX": "/Users/tester/Library/Application Support/BFME Foundation/Wine-Prefix"
        ])
    }

    // MARK: - resolveLaunch end-to-end

    func testResolveLaunchComposesWhiskyCommandAndEnvironment() async throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let exeURL = tempRoot.appendingPathComponent("lotrbfme.exe")
        try Data([0x4D, 0x5A]).write(to: exeURL) // "MZ" DOS stub

        let home = "/Users/tester"
        let sharedWine64 = home + "/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64"
        let bottlePath = home + "/Library/Containers/com.isaacmarovitz.Whisky/Bottles/B-1"
        let env = BfmeLaunchManager.Environment(
            fileExists: { path in
                if path == exeURL.path { return true }
                if path == sharedWine64 { return true }
                return false
            },
            installPathForGame: { _ in tempRoot.path },
            activeModPathForGame: { _ in "" },
            runProcess: { _, _, _, _ in 0 },
            directoryContents: { path in
                if path == home + "/Library/Containers/com.isaacmarovitz.Whisky/Bottles" {
                    return ["B-1"]
                }
                return []
            },
            modificationDate: { path in
                if path == bottlePath { return Date(timeIntervalSince1970: 1234) }
                return nil
            },
            homeDirectory: { home }
        )

        let resolved = try await BfmeLaunchManager.resolveLaunch(for: .bfme1, environment: env)
        XCTAssertEqual(resolved.game, .bfme1)
        XCTAssertEqual(resolved.compatibilityLayer, .whisky)
        XCTAssertEqual(resolved.runnerBinaryPath, sharedWine64)
        XCTAssertEqual(resolved.whiskyBottlePrefix, bottlePath)
        XCTAssertEqual(resolved.environmentOverrides["WINEPREFIX"], bottlePath)
        XCTAssertEqual(resolved.executablePath, exeURL.path)
        XCTAssertEqual(resolved.workingDirectory, tempRoot.path)
        XCTAssertTrue(resolved.arguments.isEmpty)

        let (runner, args) = BfmeLaunchManager.runnerCommand(for: resolved)
        XCTAssertEqual(runner, sharedWine64)
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
            runProcess: { _, _, _, _ in 0 },
            directoryContents: { _ in [] },
            homeDirectory: { "/Users/tester" }
        )

        let resolved = try await BfmeLaunchManager.resolveLaunch(for: .bfme2, environment: env)
        XCTAssertEqual(resolved.compatibilityLayer, .crossover)
        XCTAssertEqual(resolved.runnerBinaryPath, crossoverPath)
        XCTAssertEqual(resolved.arguments, ["-mod", modPath])
        XCTAssertTrue(resolved.environmentOverrides.isEmpty)
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
            runProcess: { _, _, _, _ in 0 },
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

    /// When Whisky.app is installed but the shared wine64 has not been
    /// downloaded yet, surface the dedicated `whiskyNotConfigured` error.
    func testResolveLaunchReportsWhiskyNotConfiguredWhenAppPresentButWineMissing() async throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let exeURL = tempRoot.appendingPathComponent("lotrbfme.exe")
        try Data([0x4D, 0x5A]).write(to: exeURL)

        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == exeURL.path || path == "/Applications/Whisky.app" },
            installPathForGame: { _ in tempRoot.path },
            activeModPathForGame: { _ in "" },
            runProcess: { _, _, _, _ in 0 },
            directoryContents: { _ in [] },
            homeDirectory: { "/Users/tester" }
        )

        do {
            _ = try await BfmeLaunchManager.resolveLaunch(for: .bfme1, environment: env)
            XCTFail("expected whiskyNotConfigured")
        } catch let error as BfmeLaunchManager.LaunchError {
            XCTAssertEqual(error, .whiskyNotConfigured)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testResolveLaunchFailsWhenExecutableMissing() async throws {
        let home = "/Users/tester"
        let sharedWine64 = home + "/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64"
        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == sharedWine64 },
            installPathForGame: { _ in "/nonexistent/install" },
            activeModPathForGame: { _ in "" },
            runProcess: { _, _, _, _ in 0 },
            directoryContents: { _ in [] },
            homeDirectory: { home }
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
            runProcess: { _, _, _, _ in 0 },
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

    // MARK: - launchGame env threading

    /// `launchGame` must forward the per-layer env overrides to
    /// `runProcess` verbatim (the defaultRunProcess merges them with
    /// `ProcessInfo.environment` before spawning).
    func testLaunchGameThreadsEnvironmentOverridesThroughRunProcess() async throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let exeURL = tempRoot.appendingPathComponent("lotrbfme.exe")
        try Data([0x4D, 0x5A]).write(to: exeURL)

        let home = "/Users/tester"
        let sharedWine64 = home + "/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64"
        let bottlePath = home + "/Library/Containers/com.isaacmarovitz.Whisky/Bottles/XYZ"

        // Capture the (binary, args, cwd, env) tuple the launch manager
        // would have spawned. Using a class so the async closure can
        // mutate it.
        final class Capture: @unchecked Sendable {
            var binary: String = ""
            var arguments: [String] = []
            var cwd: String?
            var env: [String: String] = [:]
        }
        let capture = Capture()

        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == exeURL.path || path == sharedWine64 },
            installPathForGame: { _ in tempRoot.path },
            activeModPathForGame: { _ in "" },
            runProcess: { binary, args, cwd, environment in
                capture.binary = binary
                capture.arguments = args
                capture.cwd = cwd
                capture.env = environment
                return 0
            },
            directoryContents: { path in
                if path == home + "/Library/Containers/com.isaacmarovitz.Whisky/Bottles" {
                    return ["XYZ"]
                }
                return []
            },
            modificationDate: { path in
                if path == bottlePath { return Date(timeIntervalSince1970: 500) }
                return nil
            },
            homeDirectory: { home }
        )

        try await BfmeLaunchManager.launchGame(.bfme1, environment: env)
        XCTAssertEqual(capture.binary, sharedWine64)
        XCTAssertEqual(capture.arguments, [exeURL.path])
        XCTAssertEqual(capture.env["WINEPREFIX"], bottlePath)
    }

    // MARK: - Helpers

    private func makeTempDir(file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bfme-launch-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
