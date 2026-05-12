import XCTest
@testable import BfmeLauncherApp

final class BfmeLaunchManagerTests: XCTestCase {
    func testNoCompatibilityLayerReturnsNoneDetected() {
        // A filesystem that fails every probe.
        let env = BfmeLaunchManager.Environment(
            fileExists: { _ in false },
            installPathForGame: { _ in "/tmp/bfme" },
            activeModPathForGame: { _ in "" },
            runProcess: { _, _, _ in XCTFail("should not run"); return 0 }
        )
        XCTAssertTrue(BfmeLaunchManager.detectCompatibilityLayers(environment: env).isEmpty)
    }

    func testDetectsWhiskyFromFakePrefix() throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Simulate /Applications/Whisky.app by making the probe succeed for
        // that specific path only.
        let env = BfmeLaunchManager.Environment(
            fileExists: { path in path == "/Applications/Whisky.app" },
            installPathForGame: { _ in tempRoot.path },
            activeModPathForGame: { _ in "" },
            runProcess: { _, _, _ in 0 }
        )
        let layers = BfmeLaunchManager.detectCompatibilityLayers(environment: env)
        XCTAssertEqual(layers, [.whisky])
    }

    func testResolveLaunchComposesWhiskyCommand() async throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Create the fake executable on disk so the exe-exists probe (the
        // real FileManager) succeeds too.
        let exeURL = tempRoot.appendingPathComponent("lotrbfme.exe")
        try Data([0x4D, 0x5A]).write(to: exeURL) // "MZ" DOS stub

        let env = BfmeLaunchManager.Environment(
            fileExists: { path in
                if path == exeURL.path { return true }
                if path == "/Applications/Whisky.app" { return true }
                return false
            },
            installPathForGame: { _ in tempRoot.path },
            activeModPathForGame: { _ in "" },
            runProcess: { _, _, _ in 0 }
        )

        let resolved = try await BfmeLaunchManager.resolveLaunch(for: .bfme1, environment: env)
        XCTAssertEqual(resolved.game, .bfme1)
        XCTAssertEqual(resolved.compatibilityLayer, .whisky)
        XCTAssertEqual(resolved.executablePath, exeURL.path)
        XCTAssertEqual(resolved.workingDirectory, tempRoot.path)
        XCTAssertTrue(resolved.arguments.isEmpty)

        let (runner, args) = BfmeLaunchManager.runnerCommand(for: resolved)
        XCTAssertTrue(runner.contains("Whisky"))
        XCTAssertEqual(args.first, "run")
        XCTAssertTrue(args.contains(exeURL.path))
    }

    func testResolveLaunchWithActiveModAddsModArgument() async throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let exeURL = tempRoot.appendingPathComponent("lotrbfme2.exe")
        try Data([0x4D, 0x5A]).write(to: exeURL)

        let modPath = "/Users/example/.wine/drive_c/mod"
        let env = BfmeLaunchManager.Environment(
            fileExists: { path in
                path == exeURL.path
                    || path == "/Applications/CrossOver.app"
            },
            installPathForGame: { _ in tempRoot.path },
            activeModPathForGame: { _ in modPath },
            runProcess: { _, _, _ in 0 }
        )

        let resolved = try await BfmeLaunchManager.resolveLaunch(for: .bfme2, environment: env)
        XCTAssertEqual(resolved.compatibilityLayer, .crossover)
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
            runProcess: { _, _, _ in 0 }
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
            runProcess: { _, _, _ in 0 }
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
            runProcess: { _, _, _ in 0 }
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
