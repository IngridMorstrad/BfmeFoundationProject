import XCTest
import BfmeKitCore
@testable import BfmeWineBridge

final class WinePrefixBridgeTests: XCTestCase {
    private let runtime = WineRuntime(
        binaryPath: "/opt/wine/bin/wine64",
        prefixPath: "/Users/me/Library/Application Support/BFME Foundation/Wine-Prefix"
    )

    // MARK: - Environment

    func testToolEnvironmentSetsWineprefixAndSilencesDebugOutput() {
        let env = runtime.toolEnvironment

        XCTAssertEqual(env["WINEPREFIX"], "/Users/me/Library/Application Support/BFME Foundation/Wine-Prefix")
        // winepath's stdout is the return value, so Wine's chatter must be off.
        XCTAssertEqual(env["WINEDEBUG"], "-all")
        // Stops the Mono/Gecko dialogs blocking a headless prefix update.
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "mscoree,mshtml=")
    }

    func testToolEnvironmentOmitsWineprefixWhenNoneGiven() {
        // CrossOver drives its own prefix; overriding WINEPREFIX breaks it.
        let crossover = WineRuntime(binaryPath: "/Applications/CrossOver.app/wine")
        XCTAssertNil(crossover.toolEnvironment["WINEPREFIX"])
    }

    func testExtraEnvironmentIsPreservedAndCanOverrideDefaults() {
        let gptk = WineRuntime(
            binaryPath: "/opt/wine",
            prefixPath: "/p",
            extraEnvironment: ["D3DM_SUPPORT_DXR": "1", "WINEDEBUG": "+d3d"]
        )
        XCTAssertEqual(gptk.toolEnvironment["D3DM_SUPPORT_DXR"], "1")
        XCTAssertEqual(gptk.toolEnvironment["WINEDEBUG"], "+d3d", "caller override must win")
    }

    // MARK: - Path translation

    func testWindowsPathInvokesWinepathAndTrimsTrailingNewline() throws {
        let runner = StubProcessRunner()
        runner.responses["winepath"] = ProcessResult(
            exitCode: 0,
            standardOutput: "Z:\\Users\\me\\BFME2\n",
            standardError: ""
        )
        let bridge = WinePrefixBridge(runtime: runtime, runner: runner)

        let result = try bridge.windowsPath(forUnixPath: "/Users/me/BFME2")

        XCTAssertEqual(result, "Z:\\Users\\me\\BFME2")
        XCTAssertEqual(runner.invocations.first?.executable, "/opt/wine/bin/wine64")
        XCTAssertEqual(runner.invocations.first?.arguments, ["winepath", "--windows", "/Users/me/BFME2"])
    }

    func testUnixPathInvokesWinepathWithUnixFlag() throws {
        let runner = StubProcessRunner()
        runner.responses["winepath"] = ProcessResult(exitCode: 0, standardOutput: "/Users/me/BFME2\n", standardError: "")
        let bridge = WinePrefixBridge(runtime: runtime, runner: runner)

        XCTAssertEqual(try bridge.unixPath(forWindowsPath: "Z:\\Users\\me\\BFME2"), "/Users/me/BFME2")
        XCTAssertEqual(runner.invocations.first?.arguments, ["winepath", "--unix", "Z:\\Users\\me\\BFME2"])
    }

    func testEmptyTranslationThrowsRatherThanReturningEmptyString() {
        let runner = StubProcessRunner()
        runner.responses["winepath"] = ProcessResult(exitCode: 0, standardOutput: "\n", standardError: "")
        let bridge = WinePrefixBridge(runtime: runtime, runner: runner)

        // Silently returning "" would land an empty InstallPath in the registry
        // and the game would report itself as not installed.
        XCTAssertThrowsError(try bridge.windowsPath(forUnixPath: "/Users/me/BFME2")) { error in
            XCTAssertEqual(error as? WineBridgeError, .emptyPathTranslation(input: "/Users/me/BFME2"))
        }
    }

    func testFailingToolThrowsWithStderrMessage() {
        let runner = StubProcessRunner()
        runner.responses["winepath"] = ProcessResult(exitCode: 2, standardOutput: "", standardError: "boom\n")
        let bridge = WinePrefixBridge(runtime: runtime, runner: runner)

        XCTAssertThrowsError(try bridge.windowsPath(forUnixPath: "/x")) { error in
            XCTAssertEqual(error as? WineBridgeError, .toolFailed(tool: "winepath", exitCode: 2, message: "boom"))
        }
    }

    // MARK: - Registry import

    func testImportRegistryWritesUtf16DocumentAndInvokesRegeditSilently() throws {
        let runner = StubProcessRunner()
        let bridge = WinePrefixBridge(runtime: runtime, runner: runner)

        var document = RegistryDocument()
        document.add(RegistryKeyEntry(hive: .localMachine, path: #"SOFTWARE\Test"#, values: [
            (name: "InstallPath", value: .string(#"Z:\games\bfme2\"#))
        ]))

        try bridge.importRegistry(document)

        let regedit = runner.invocations.first { $0.arguments.first == "regedit" }
        XCTAssertNotNil(regedit)
        XCTAssertEqual(regedit?.arguments[1], "/S", "import must be silent or it blocks on a dialog")
        XCTAssertEqual(regedit?.environment["WINEPREFIX"], runtime.prefixPath)

        XCTAssertEqual(runner.capturedRegFiles.count, 1)
        XCTAssertTrue(runner.capturedRegFiles[0].contains(#""InstallPath"="Z:\\games\\bfme2\\""#))
    }

    func testImportRegistryCleansUpItsTemporaryFile() throws {
        let runner = StubProcessRunner()
        let bridge = WinePrefixBridge(runtime: runtime, runner: runner)

        var document = RegistryDocument()
        document.add(RegistryKeyEntry(hive: .localMachine, path: "SOFTWARE\\T", values: [
            (name: "N", value: .string("v"))
        ]))
        try bridge.importRegistry(document)

        let path = runner.invocations.first { $0.arguments.first == "regedit" }?.arguments.last
        XCTAssertNotNil(path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path!), "temp .reg file leaked")
    }

    func testImportRegistryOfEmptyDocumentDoesNothing() throws {
        let runner = StubProcessRunner()
        let bridge = WinePrefixBridge(runtime: runtime, runner: runner)

        try bridge.importRegistry(RegistryDocument())

        XCTAssertTrue(runner.invocations.isEmpty)
    }

    // MARK: - Registry readback

    func testReadValuesReturnsNilWhenRegeditProducesNoFile() throws {
        // regedit writes no file at all for a key that does not exist, which is
        // how "game not installed" is detected.
        let runner = StubProcessRunner()
        let bridge = WinePrefixBridge(runtime: runtime, runner: runner)

        XCTAssertNil(try bridge.readValues(hive: .localMachine, path: #"SOFTWARE\Nope"#))
    }

    func testReadValuesInvokesRegeditExportForTheRequestedKey() throws {
        let runner = StubProcessRunner()
        let bridge = WinePrefixBridge(runtime: runtime, runner: runner)

        _ = try bridge.readValues(hive: .localMachine, path: #"SOFTWARE\X"#)

        let call = try XCTUnwrap(runner.invocations.first)
        XCTAssertEqual(call.arguments.first, "regedit")
        XCTAssertEqual(call.arguments[1], "/E")
        XCTAssertEqual(call.arguments.last, #"HKEY_LOCAL_MACHINE\SOFTWARE\X"#)
        XCTAssertEqual(call.environment["WINEPREFIX"], runtime.prefixPath)
    }
}
