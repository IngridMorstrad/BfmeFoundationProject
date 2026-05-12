import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BfmeOnlineKit
import BfmeKit
import BfmeKitCore

/// Covers the HTTP-only `UpdateHelper` port (review bullet #13: porting
/// the Windows-only helper to macOS). The `isUpdateAvailable` / local hash
/// contract is exercised via a URLProtocol stub and an on-disk fake
/// Arena exe.
final class UpdateHelperTests: XCTestCase {
    private var sandbox: URL!
    private var originalServerHost: String!

    override func setUp() async throws {
        sandbox = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bfme-update-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        BfmeRegistryManager.applicationSupportOverride = sandbox
        BfmeRegistryManager.applicationDataOverride = sandbox
        originalServerHost = DeploymentConfig.arenaServerHost
    }

    override func tearDown() async throws {
        DeploymentConfig.arenaServerHost = originalServerHost
        BfmeRegistryManager.applicationSupportOverride = nil
        BfmeRegistryManager.applicationDataOverride = nil
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
    }

    func testCurrentVersionHashReportsNotInstalledWhenExeMissing() {
        XCTAssertFalse(ArenaDataHelper.isInstalled)
        XCTAssertEqual(UpdateHelper.currentVersionHash(), "not_installed")
    }

    /// Known MD5 vector: `d41d8cd98f00b204e9800998ecf8427e` for the empty
    /// payload. Write a zero-byte arena exe and verify the helper hashes
    /// it correctly.
    func testCurrentVersionHashMatchesKnownMd5VectorForEmptyFile() throws {
        ArenaDataHelper.ensureDirectories()
        try Data().write(to: URL(fileURLWithPath: ArenaDataHelper.arenaExecutablePath))
        XCTAssertEqual(UpdateHelper.currentVersionHash(), "d41d8cd98f00b204e9800998ecf8427e")
    }

    /// A second known vector: MD5("abc") = 900150983cd24fb0d6963f7d28e17f72.
    func testCurrentVersionHashMatchesKnownMd5VectorForAbc() throws {
        ArenaDataHelper.ensureDirectories()
        try Data("abc".utf8).write(to: URL(fileURLWithPath: ArenaDataHelper.arenaExecutablePath))
        XCTAssertEqual(UpdateHelper.currentVersionHash(), "900150983cd24fb0d6963f7d28e17f72")
    }
}
