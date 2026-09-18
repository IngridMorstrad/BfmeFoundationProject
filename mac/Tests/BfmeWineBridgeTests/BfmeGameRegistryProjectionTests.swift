import XCTest
import BfmeKitCore
@testable import BfmeWineBridge

final class BfmeGameRegistryProjectionTests: XCTestCase {
    private func state(game: Int = 1) -> BfmeGameRegistryState {
        BfmeGameRegistryState(
            game: game,
            installPathUnix: "/Users/me/Games/BFME2",
            language: "English",
            serialKey: "ABCDEFGHIJKLMNOPQRST"
        )
    }

    // MARK: - Dual-root writes

    func testWritesBothPlainAndWow6432NodeCopies() {
        let document = BfmeGameRegistryProjection.document(
            for: state(),
            installPathWindows: #"Z:\Users\me\Games\BFME2"#
        )
        let paths = document.entries.map(\.path)

        // A 32-bit game in a 64-bit prefix only ever sees the WOW6432Node copy;
        // in a 32-bit prefix only the plain copy exists. Both are required for
        // the projection to work without detecting the prefix architecture.
        XCTAssertTrue(paths.contains(#"SOFTWARE\Electronic Arts\Electronic Arts\The Battle for Middle-earth II"#))
        XCTAssertTrue(paths.contains(#"SOFTWARE\WOW6432Node\Electronic Arts\Electronic Arts\The Battle for Middle-earth II"#))
    }

    func testUsesCorrectRegistryKeyPerGame() {
        let expected = [
            0: #"SOFTWARE\WOW6432Node\Electronic Arts\EA Games\The Battle for Middle-earth"#,
            1: #"SOFTWARE\WOW6432Node\Electronic Arts\Electronic Arts\The Battle for Middle-earth II"#,
            2: #"SOFTWARE\WOW6432Node\Electronic Arts\Electronic Arts\The Lord of the Rings, The Rise of the Witch-king"#
        ]
        for (game, path) in expected {
            let document = BfmeGameRegistryProjection.document(for: state(game: game), installPathWindows: #"Z:\g"#)
            XCTAssertTrue(document.entries.map(\.path).contains(path), "game \(game) wrote the wrong key")
        }
    }

    // MARK: - Install path shape

    func testInstallPathGetsTrailingBackslash() {
        let document = BfmeGameRegistryProjection.document(
            for: state(),
            installPathWindows: #"Z:\Users\me\Games\BFME2"#
        )
        let value = document.entries
            .first { $0.path.hasPrefix("SOFTWARE\\Electronic") }?
            .values.first { $0.name == "InstallPath" }?.value

        // The games concatenate rather than join, so a missing separator
        // produces "...BFME2lotrbfme2ep1.exe".
        XCTAssertEqual(value, .string(#"Z:\Users\me\Games\BFME2\"#))
    }

    func testExistingTrailingBackslashIsNotDoubled() {
        let document = BfmeGameRegistryProjection.document(
            for: state(),
            installPathWindows: #"Z:\Users\me\Games\BFME2\"#
        )
        let value = document.entries
            .first { $0.path.hasPrefix("SOFTWARE\\Electronic") }?
            .values.first { $0.name == "InstallPath" }?.value

        XCTAssertEqual(value, .string(#"Z:\Users\me\Games\BFME2\"#))
    }

    func testInstallPathIsAWindowsPathNotAPosixPath() {
        let document = BfmeGameRegistryProjection.document(
            for: state(),
            installPathWindows: #"Z:\Users\me\Games\BFME2"#
        )
        let serialized = document.serialize()

        // The whole bug this module fixes: a POSIX path in InstallPath is
        // unusable by the Windows executable.
        XCTAssertFalse(serialized.contains("\"InstallPath\"=\"/Users"))
    }

    // MARK: - Required values

    func testWritesEveryValueTheGameReads() {
        let document = BfmeGameRegistryProjection.document(for: state(), installPathWindows: #"Z:\g"#)
        let gameKey = document.entries.first { $0.path.hasPrefix("SOFTWARE\\WOW6432Node\\Electronic") }

        let names = Set(gameKey?.values.map(\.name) ?? [])
        XCTAssertEqual(names, ["InstallPath", "Language", "MapPackVersion", "UseLocalUserMaps", "UserDataLeafName", "Version"])
    }

    func testSerialKeyGoesInErgcSubkeyAsDefaultValue() {
        let document = BfmeGameRegistryProjection.document(for: state(), installPathWindows: #"Z:\g"#)
        let ergc = document.entries.first { $0.path.hasSuffix(#"\ergc"#) }

        XCTAssertNotNil(ergc)
        XCTAssertEqual(ergc?.values.count, 1)
        XCTAssertEqual(ergc?.values.first?.name, "")
        XCTAssertEqual(ergc?.values.first?.value, .string("ABCDEFGHIJKLMNOPQRST"))
    }

    func testUserDataLeafNameDefaultsPerGame() {
        for (game, leaf) in [0: "My Battle for Middle-earth Files",
                             1: "My Battle for Middle-earth II Files",
                             2: "My Rise of the Witch-king Files"] {
            let document = BfmeGameRegistryProjection.document(for: state(game: game), installPathWindows: #"Z:\g"#)
            let value = document.entries
                .first { $0.path.hasPrefix("SOFTWARE\\WOW6432Node\\Electronic") }?
                .values.first { $0.name == "UserDataLeafName" }?.value
            XCTAssertEqual(value, .string(leaf), "game \(game)")
        }
    }

    func testAppPathsEntryPointsAtTheExecutable() {
        let document = BfmeGameRegistryProjection.document(for: state(game: 2), installPathWindows: #"Z:\g"#)
        let appPaths = document.entries.first {
            $0.path == #"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\lotrbfme2ep1.exe"#
        }

        XCTAssertNotNil(appPaths)
        XCTAssertEqual(appPaths?.values.first { $0.name == "" }?.value, .string(#"Z:\g\lotrbfme2ep1.exe"#))
        XCTAssertEqual(appPaths?.values.first { $0.name == "Installed" }?.value, .dword(1))
        XCTAssertEqual(appPaths?.values.first { $0.name == "Path" }?.value, .string(#"Z:\g\"#))
    }

    func testVersionDefaultsMatchTheWindowsLauncher() {
        let document = BfmeGameRegistryProjection.document(for: state(), installPathWindows: #"Z:\g"#)
        let gameKey = document.entries.first { $0.path.hasPrefix("SOFTWARE\\WOW6432Node\\Electronic") }

        XCTAssertEqual(gameKey?.values.first { $0.name == "Version" }?.value, .dword(65539))
        XCTAssertEqual(gameKey?.values.first { $0.name == "MapPackVersion" }?.value, .dword(65536))
        XCTAssertEqual(gameKey?.values.first { $0.name == "UseLocalUserMaps" }?.value, .dword(0))
    }

    // MARK: - project()

    func testProjectTranslatesThePathThenImports() throws {
        let runner = StubProcessRunner()
        runner.responses["winepath"] = ProcessResult(
            exitCode: 0,
            standardOutput: "Z:\\Users\\me\\Games\\BFME2\n",
            standardError: ""
        )
        let bridge = WinePrefixBridge(
            runtime: WineRuntime(binaryPath: "/opt/wine", prefixPath: "/p"),
            runner: runner
        )

        let written = try BfmeGameRegistryProjection.project(state(), through: bridge)

        XCTAssertEqual(written, #"Z:\Users\me\Games\BFME2"#)

        let tools = runner.invocations.compactMap(\.arguments.first)
        guard let winepathIndex = tools.firstIndex(of: "winepath"),
              let regeditIndex = tools.firstIndex(of: "regedit") else {
            return XCTFail("expected both a winepath translation and a regedit import, got \(tools)")
        }
        XCTAssertLessThan(winepathIndex, regeditIndex, "path must be translated before it is written")

        XCTAssertEqual(runner.capturedRegFiles.count, 1)
        XCTAssertTrue(runner.capturedRegFiles[0].contains(#""InstallPath"="Z:\\Users\\me\\Games\\BFME2\\""#))
    }

    func testProjectDoesNotImportWhenTranslationFails() {
        let runner = StubProcessRunner()
        runner.responses["winepath"] = ProcessResult(exitCode: 1, standardOutput: "", standardError: "no prefix")
        let bridge = WinePrefixBridge(runtime: WineRuntime(binaryPath: "/opt/wine", prefixPath: "/p"), runner: runner)

        XCTAssertThrowsError(try BfmeGameRegistryProjection.project(state(), through: bridge))
        // Importing a document built on a failed translation would write a
        // broken InstallPath.
        XCTAssertFalse(runner.invocations.contains { $0.arguments.first == "regedit" })
    }

    func testInstalledPathReadbackPrefersWow6432NodeCopy() throws {
        let runner = StubProcessRunner()
        // Serve a real export document for whichever key regedit is asked for.
        var document = RegistryDocument()
        document.add(RegistryKeyEntry(
            hive: .localMachine,
            path: #"SOFTWARE\WOW6432Node\Electronic Arts\Electronic Arts\The Battle for Middle-earth II"#,
            values: [(name: "InstallPath", value: .string(#"Z:\from\wow6432node\"#))]
        ))
        runner.exportDocument = document
        let bridge = WinePrefixBridge(runtime: WineRuntime(binaryPath: "/opt/wine", prefixPath: "/p"), runner: runner)

        let value = try BfmeGameRegistryProjection.installedPathAsGameSeesIt(game: 1, through: bridge)

        XCTAssertEqual(value, #"Z:\from\wow6432node\"#)
        // WOW6432Node is what a 32-bit process resolves to, so query it first.
        XCTAssertEqual(
            runner.invocations.first?.arguments.last,
            #"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Electronic Arts\Electronic Arts\The Battle for Middle-earth II"#
        )
    }
}
