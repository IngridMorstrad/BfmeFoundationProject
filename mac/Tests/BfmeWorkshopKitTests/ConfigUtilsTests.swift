import XCTest
@testable import BfmeWorkshopKit
import BfmeKit
import BfmeKitCore

final class ConfigUtilsTests: XCTestCase {
    private var sandbox: URL!

    override func setUp() async throws {
        sandbox = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bfme-configutils-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
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

    func testGetVirtualRegistryMirrorsStoredKeys() async throws {
        // Seed the BFME2 install location and user-data leaf name.
        let install = sandbox.appendingPathComponent("Games/BFME2", isDirectory: true)
        try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
        try await BfmeRegistryManager.setKeyValue(1, .installPath, install.path + "/")
        try await BfmeRegistryManager.setKeyValue(1, .language, "English")
        try await BfmeRegistryManager.setKeyValue(1, .userDataLeafName, "My Battle for Middle-earth II Files")

        let registry = await ConfigUtils.getVirtualRegistry()
        XCTAssertEqual(registry.count, 3) // games 0, 1, 2

        let bfme2 = try XCTUnwrap(registry[1])
        XCTAssertEqual(bfme2.gameLanguage, "EN")
        XCTAssertEqual(bfme2.dataDirectory, "My Battle for Middle-earth II Files")
        XCTAssertTrue(bfme2.gameDirectory.contains("bfme2"),
                      "install path should be normalised and lowercased: \(bfme2.gameDirectory)")
    }

    func testEnableAndDisableEnhancementRoundTripsThroughDisk() async {
        var enhancements: [String: BfmeWorkshopEntry] = [:]
        let entry = BfmeWorkshopEntry(
            guid: "enh-1",
            name: "Sharper Shadows",
            version: "1.0",
            game: 1,
            type: 4
        )

        ConfigUtils.enableEnhancement(entry, activeEnhancements: &enhancements)
        XCTAssertEqual(enhancements["enh-1"], entry)

        let persisted = (ConfigUtils.configDirectory as NSString)
            .appendingPathComponent("active_enhancements_1.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: persisted))

        let decoded: [String: BfmeWorkshopEntry] = FileUtils.readJSON(path: persisted, default: [:])
        XCTAssertEqual(decoded["enh-1"]?.guid, "enh-1")

        ConfigUtils.disableEnhancement(entry, activeEnhancements: &enhancements)
        XCTAssertNil(enhancements["enh-1"])
        let reloaded: [String: BfmeWorkshopEntry] = FileUtils.readJSON(path: persisted, default: [:])
        XCTAssertTrue(reloaded.isEmpty)
    }

    func testSaveActivePatchCascadesRotwkToBfme2() async {
        let rotwk = BfmeWorkshopEntry(
            guid: "rotwk-patch",
            name: "RotWK Patch",
            version: "2.02",
            game: 2,
            type: 0
        )
        await ConfigUtils.saveActivePatch(rotwk)

        let rotwkPath = (ConfigUtils.configDirectory as NSString)
            .appendingPathComponent("active_patch_2.json")
        let bfme2Path = (ConfigUtils.configDirectory as NSString)
            .appendingPathComponent("active_patch_1.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: rotwkPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bfme2Path))

        let bfme2: BfmeWorkshopEntry = FileUtils.readJSON(path: bfme2Path, default: BfmeWorkshopEntry())
        XCTAssertEqual(bfme2.guid, "original-BFME2")
        XCTAssertEqual(bfme2.game, 1)
    }

    func testSaveAndReadSyncProgress() {
        ConfigUtils.saveSyncProgress(game: 1, progress: 42, status: "Downloading")
        let path = (ConfigUtils.configDirectory as NSString)
            .appendingPathComponent("active_patch_1.syncing")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        let read = ConfigUtils.readSyncProgress(fromFile: path)
        XCTAssertEqual(read.progress, 42)
        XCTAssertEqual(read.status, "Downloading")

        ConfigUtils.saveSyncProgress(game: 1, progress: -1, status: "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testSaveActiveModWritesAndClearsModTxt() async throws {
        let install = sandbox.appendingPathComponent("Games/BFME2", isDirectory: true)
        try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
        try await BfmeRegistryManager.setKeyValue(1, .installPath, install.path + "/")

        await ConfigUtils.saveActiveMod(game: 1, modPath: "MyMod")
        let modTxt = install.appendingPathComponent("mod.txt").path
        XCTAssertEqual(FileUtils.readText(path: modTxt), "MyMod")

        await ConfigUtils.saveActiveMod(game: 1, modPath: "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: modTxt))
    }
}
