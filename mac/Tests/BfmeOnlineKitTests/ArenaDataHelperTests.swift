import XCTest
@testable import BfmeOnlineKit
import BfmeKit
import BfmeKitCore

final class ArenaDataHelperTests: XCTestCase {
    private var sandbox: URL!
    private var originalServerHost: String!
    private var originalFilesHost: String!

    override func setUp() async throws {
        sandbox = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bfme-arena-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        BfmeRegistryManager.applicationSupportOverride = sandbox
        BfmeRegistryManager.applicationDataOverride = sandbox
        originalServerHost = DeploymentConfig.arenaServerHost
        originalFilesHost = DeploymentConfig.arenaFilesHost
    }

    override func tearDown() async throws {
        DeploymentConfig.arenaServerHost = originalServerHost
        DeploymentConfig.arenaFilesHost = originalFilesHost
        BfmeRegistryManager.applicationSupportOverride = nil
        BfmeRegistryManager.applicationDataOverride = nil
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
    }

    func testVersionHashURLContainsBranchAndApplicationName() {
        let url = ArenaDataHelper.versionHashURL(branch: "beta")
        XCTAssertTrue(url.hasPrefix(DeploymentConfig.arenaServerHost),
                      "URL should start with deployment host: \(url)")
        XCTAssertTrue(url.contains("/api/applications/versionHash"))
        XCTAssertTrue(url.contains("name=online-arena"))
        XCTAssertTrue(url.contains("version=beta"))
    }

    func testVersionHashURLFallsBackToTildeForEmptyBranch() {
        let url = ArenaDataHelper.versionHashURL(branch: "")
        XCTAssertTrue(url.contains("version=~"), "empty branch should become '~': \(url)")
    }

    func testBinaryURLIsRootedAtFilesHost() {
        DeploymentConfig.arenaFilesHost = "https://files.test.local"
        let url = ArenaDataHelper.binaryURL(branch: "stable")
        XCTAssertEqual(url, "https://files.test.local/application-builds/online-arena-stable")
    }

    func testEnsureDirectoriesCreatesInstallAndDataRoot() {
        ArenaDataHelper.ensureDirectories()
        XCTAssertTrue(FileManager.default.fileExists(atPath: ArenaDataHelper.globalInstallPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ArenaDataHelper.globalDataPath))
    }

    func testIsInstalledReflectsExecutablePresence() throws {
        ArenaDataHelper.ensureDirectories()
        XCTAssertFalse(ArenaDataHelper.isInstalled)

        try Data("stub".utf8).write(
            to: URL(fileURLWithPath: ArenaDataHelper.arenaExecutablePath)
        )
        XCTAssertTrue(ArenaDataHelper.isInstalled)
    }

    /// The backend returns a JSON `{ "VersionHash": "deadbeef" }` response.
    /// We exercise the decoder shape the helper would use if it was
    /// consuming that payload directly.
    func testVersionHashResponseDecodes() throws {
        struct VersionHashResponse: Codable {
            let versionHash: String
            enum CodingKeys: String, CodingKey { case versionHash = "VersionHash" }
        }

        let json = #"{"VersionHash":"deadbeef"}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(VersionHashResponse.self, from: data)
        XCTAssertEqual(decoded.versionHash, "deadbeef")
    }
}
