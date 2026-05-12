import XCTest
@testable import BfmeKit
import BfmeKitCore

final class BfmeSettingsManagerTests: XCTestCase {
    private var sandbox: URL!

    override func setUp() async throws {
        sandbox = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bfme-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        BfmeRegistryManager.applicationSupportOverride = sandbox
        BfmeRegistryManager.applicationDataOverride = sandbox
        try await RegistryStore.shared.reset()

        // Seed a UserDataLeafName so settings land inside our temp dir.
        try await BfmeRegistryManager.setKeyValue(1, .userDataLeafName, "TestLeaf")
    }

    override func tearDown() async throws {
        try await RegistryStore.shared.reset()
        BfmeRegistryManager.applicationSupportOverride = nil
        BfmeRegistryManager.applicationDataOverride = nil
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
    }

    func testSetThenGetRoundTripsThroughDisk() async throws {
        try await BfmeSettingsManager.set(1, "Resolution", "2560 1440")
        let value = await BfmeSettingsManager.get(1, "Resolution")
        XCTAssertEqual(value, "2560 1440")

        let url = sandbox
            .appendingPathComponent("TestLeaf")
            .appendingPathComponent("Options.ini")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("Resolution = 2560 1440"))
    }

    func testGetOnMissingReturnsNil() async {
        let value = await BfmeSettingsManager.get(1, "DoesNotExist")
        XCTAssertNil(value)
    }

    func testSetSeedsFromDefaultOptionsWhenFileMissing() async throws {
        try await BfmeSettingsManager.set(1, "MusicVolume", "42.000000")

        let fromDisk = await BfmeSettingsManager.get(1, "MusicVolume")
        XCTAssertEqual(fromDisk, "42.000000")

        // Every other default option must still be persisted since the
        // `set` call seeds from `BfmeDefaults.defaultOptions` on first write.
        let brightness = await BfmeSettingsManager.get(1, "Brightness")
        XCTAssertEqual(brightness, "50")
    }
}
