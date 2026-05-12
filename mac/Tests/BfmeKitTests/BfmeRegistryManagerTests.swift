import XCTest
@testable import BfmeKit
import BfmeKitCore

final class BfmeRegistryManagerTests: XCTestCase {
    private var sandbox: URL!
    private var fakeInstallDir: URL!

    override func setUp() async throws {
        sandbox = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bfme-regmgr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        fakeInstallDir = sandbox.appendingPathComponent("BFME2Install", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeInstallDir, withIntermediateDirectories: true)

        BfmeRegistryManager.applicationSupportOverride = sandbox
        BfmeRegistryManager.applicationDataOverride = sandbox
        try await RegistryStore.shared.reset()
    }

    override func tearDown() async throws {
        try await RegistryStore.shared.reset()
        BfmeRegistryManager.applicationSupportOverride = nil
        BfmeRegistryManager.applicationDataOverride = nil
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
    }

    func testGetKeyValueBeforeInstallReturnsEmpty() async {
        let value = await BfmeRegistryManager.getKeyValue(1, .installPath)
        XCTAssertEqual(value, "")
        let installed = await BfmeRegistryManager.isInstalled(1)
        XCTAssertFalse(installed)
    }

    func testCreateNewInstallRegistryFlipsIsInstalled() async throws {
        try await BfmeRegistryManager.createNewInstallRegistry(
            1,
            installPath: fakeInstallDir.path,
            language: "English"
        )

        let installed = await BfmeRegistryManager.isInstalled(1)
        XCTAssertTrue(installed)
        let installPath = await BfmeRegistryManager.getKeyValue(1, .installPath)
        XCTAssertTrue(installPath.hasPrefix(fakeInstallDir.path))
        let language = await BfmeRegistryManager.getKeyValue(1, .language)
        XCTAssertEqual(language, "English")
        let version = await BfmeRegistryManager.getKeyValue(1, .version)
        XCTAssertEqual(version, "65539")
        let leaf = await BfmeRegistryManager.getKeyValue(1, .userDataLeafName)
        XCTAssertEqual(leaf, "My Battle for Middle-earth II Files")
    }

    func testCreateNewInstallWritesOptionsIniIntoUserDataLeaf() async throws {
        try await BfmeRegistryManager.createNewInstallRegistry(
            1,
            installPath: fakeInstallDir.path,
            language: "English"
        )

        let optionsURL = sandbox
            .appendingPathComponent("My Battle for Middle-earth II Files")
            .appendingPathComponent("Options.ini")
        XCTAssertTrue(FileManager.default.fileExists(atPath: optionsURL.path))
        let contents = try String(contentsOf: optionsURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("Resolution = 1920 1080"))
    }

    func testGameLanguageCodeMapping() {
        XCTAssertEqual(BfmeRegistryManager.gameLanguageToLanguageCode("German"), "DE")
        XCTAssertEqual(BfmeRegistryManager.gameLanguageToLanguageCode("english uk"), "EN")
        XCTAssertEqual(BfmeRegistryManager.gameLanguageToLanguageCode("klingon"), "klingon")

        XCTAssertEqual(BfmeRegistryManager.gameLanguageCodeToLanguage("DE"), "German")
        XCTAssertEqual(BfmeRegistryManager.gameLanguageCodeToLanguage("en"), "English")
        XCTAssertEqual(BfmeRegistryManager.gameLanguageCodeToLanguage("xx"), "xx")

        // Round-trip via the canonical mapping.
        let code = BfmeRegistryManager.gameLanguageToLanguageCode("German")
        XCTAssertEqual(BfmeRegistryManager.gameLanguageCodeToLanguage(code), "German")
    }

    func testGameNameToInt() {
        XCTAssertEqual(BfmeRegistryManager.gameNameToInt("BFME1"), 0)
        XCTAssertEqual(BfmeRegistryManager.gameNameToInt("bfme2"), 1)
        XCTAssertEqual(BfmeRegistryManager.gameNameToInt("ROTWK"), 2)
        XCTAssertEqual(BfmeRegistryManager.gameNameToInt("Unknown"), 0)
    }

    func testEnsureCompatibilitySettingsIsNoOpOnMac() async {
        // No side effect expected; the method must simply return.
        BfmeRegistryManager.ensureCompatibilitySettings("/nonexistent/game.exe")
        let key = #"SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"#
        let exists = await RegistryStore.shared.openSubKey(hive: .hkcu, path: key)
        XCTAssertFalse(exists)
    }
}
