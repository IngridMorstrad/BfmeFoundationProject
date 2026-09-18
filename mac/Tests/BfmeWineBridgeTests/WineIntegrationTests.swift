import XCTest
import BfmeKitCore
@testable import BfmeWineBridge

/// Exercises the bridge against a real Wine install and a real throwaway
/// prefix, which is the only way to prove the `.reg` encoding, the WOW64
/// redirection assumption and the `reg query` parsing are actually right
/// rather than merely self-consistent.
///
/// Skipped unless a Wine binary is provided, so the normal `swift test` run and
/// CI stay hermetic:
///
///     BFME_TEST_WINE_BIN=/path/to/bin/wine swift test --filter WineIntegrationTests
final class WineIntegrationTests: XCTestCase {
    private var wineBinary: String?
    private var prefixURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        wineBinary = ProcessInfo.processInfo.environment["BFME_TEST_WINE_BIN"]
        try XCTSkipIf(wineBinary == nil, "set BFME_TEST_WINE_BIN to run the real-Wine integration tests")

        prefixURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bfme-itest-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let prefixURL, FileManager.default.fileExists(atPath: prefixURL.path) {
            try? FileManager.default.removeItem(at: prefixURL)
        }
        try super.tearDownWithError()
    }

    private func makeBridge() throws -> WinePrefixBridge {
        let bridge = WinePrefixBridge(
            runtime: WineRuntime(binaryPath: try XCTUnwrap(wineBinary), prefixPath: prefixURL.path)
        )
        try bridge.ensurePrefixInitialised()
        return bridge
    }

    /// A prefix really does get built, and `winepath` round trips a macOS path.
    func testPathTranslationRoundTripsThroughARealPrefix() throws {
        let bridge = try makeBridge()

        let installDir = prefixURL.appendingPathComponent("GameDir")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let windowsPath = try bridge.windowsPath(forUnixPath: installDir.path)

        // Must be a drive-letter path, not a POSIX one.
        XCTAssertTrue(
            windowsPath.count > 2 && windowsPath.dropFirst(1).hasPrefix(":\\"),
            "expected a Windows drive path, got '\(windowsPath)'"
        )

        let backAgain = try bridge.unixPath(forWindowsPath: windowsPath)
        XCTAssertEqual(
            URL(fileURLWithPath: backAgain).resolvingSymlinksInPath().path,
            installDir.resolvingSymlinksInPath().path
        )
    }

    /// The whole point: after projecting, a 32-bit process reading the plain
    /// `SOFTWARE\Electronic Arts\...` path finds the install. This is the read
    /// the actual game performs.
    func testProjectedInstallIsVisibleThroughThe32BitViewTheGameUses() throws {
        let bridge = try makeBridge()

        let installDir = prefixURL.appendingPathComponent("BFME2")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let state = BfmeGameRegistryState(
            game: 1,
            installPathUnix: installDir.path,
            language: "English",
            serialKey: "ABCDEFGHIJKLMNOPQRST"
        )

        let writtenWindowsPath = try BfmeGameRegistryProjection.project(state, through: bridge)

        let gameKey = #"SOFTWARE\Electronic Arts\Electronic Arts\The Battle for Middle-earth II"#
        // Read the WOW6432Node copy: that is precisely what a 32-bit process
        // asking for `gameKey` is redirected to.
        let asGameSeesIt = try bridge.readStringValue(
            hive: .localMachine,
            path: #"SOFTWARE\WOW6432Node\"# + gameKey.replacingOccurrences(of: "SOFTWARE\\", with: ""),
            name: "InstallPath"
        )

        XCTAssertEqual(asGameSeesIt, writtenWindowsPath + "\\")
    }

    /// Every value the game reads survives the round trip with the right type.
    func testAllProjectedValuesReadBackCorrectly() throws {
        let bridge = try makeBridge()

        let installDir = prefixURL.appendingPathComponent("RotWK")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        try BfmeGameRegistryProjection.project(
            BfmeGameRegistryState(
                game: 2,
                installPathUnix: installDir.path,
                language: "German",
                serialKey: "ZZZZZZZZZZZZZZZZZZZZ"
            ),
            through: bridge
        )

        let key = #"SOFTWARE\WOW6432Node\Electronic Arts\Electronic Arts\The Lord of the Rings, The Rise of the Witch-king"#

        XCTAssertEqual(
            try bridge.readStringValue(hive: .localMachine, path: key, name: "Language"),
            "German"
        )
        XCTAssertEqual(
            try bridge.readStringValue(hive: .localMachine, path: key, name: "UserDataLeafName"),
            "My Rise of the Witch-king Files"
        )
        // dwords come back typed, not as a hex string.
        XCTAssertEqual(
            try bridge.readValue(hive: .localMachine, path: key, name: "Version"),
            .dword(65539)
        )
        // The serial is the default value of the ergc subkey.
        XCTAssertEqual(
            try bridge.readStringValue(hive: .localMachine, path: key + #"\ergc"#, name: ""),
            "ZZZZZZZZZZZZZZZZZZZZ"
        )
    }

    /// App Paths resolution, used by the game and its patchers to find the exe
    /// by name.
    func testAppPathsEntryIsReadableByName() throws {
        let bridge = try makeBridge()

        let installDir = prefixURL.appendingPathComponent("BFME1")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        try BfmeGameRegistryProjection.project(
            BfmeGameRegistryState(
                game: 0,
                installPathUnix: installDir.path,
                language: "English",
                serialKey: "AAAAAAAAAAAAAAAAAAAA"
            ),
            through: bridge
        )

        let value = try bridge.readStringValue(
            hive: .localMachine,
            path: #"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\lotrbfme.exe"#,
            name: ""
        )

        XCTAssertEqual(value?.hasSuffix(#"\lotrbfme.exe"#), true, "got '\(value ?? "nil")'")
    }

    /// A non-ASCII install path is exactly why the document is UTF-16LE.
    func testNonAsciiInstallPathSurvivesTheRoundTrip() throws {
        let bridge = try makeBridge()

        let installDir = prefixURL.appendingPathComponent("Bilbó Béutlin")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let written = try BfmeGameRegistryProjection.project(
            BfmeGameRegistryState(
                game: 1,
                installPathUnix: installDir.path,
                language: "English",
                serialKey: "BBBBBBBBBBBBBBBBBBBB"
            ),
            through: bridge
        )

        XCTAssertTrue(written.contains("Bilbó"), "winepath lost the non-ASCII segment: \(written)")

        let readBack = try BfmeGameRegistryProjection.installedPathAsGameSeesIt(game: 1, through: bridge)
        XCTAssertEqual(readBack, written + "\\")
    }

    /// Absent keys report nil rather than throwing.
    func testQueryingAnAbsentGameReturnsNil() throws {
        let bridge = try makeBridge()
        XCTAssertNil(try BfmeGameRegistryProjection.installedPathAsGameSeesIt(game: 0, through: bridge))
    }

    /// The prefix's %APPDATA% resolves to a real directory, which is where
    /// Options.ini has to be written for the game to read it.
    func testApplicationDataDirectoryResolvesInsideThePrefix() throws {
        let bridge = try makeBridge()

        let appData = try bridge.applicationDataDirectory()

        XCTAssertTrue(appData.contains("drive_c"), "expected a path inside the prefix, got '\(appData)'")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: appData),
            "%APPDATA% should exist in an initialised prefix: \(appData)"
        )
    }
}
