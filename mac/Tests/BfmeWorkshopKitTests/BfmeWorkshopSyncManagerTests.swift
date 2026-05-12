import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BfmeWorkshopKit
import BfmeKit
import BfmeKitCore
import BfmeHttpInstruments

/// Exercises the `BfmeWorkshopSyncManager.sync` path against a real
/// temp-rooted `RegistryStore` and a URLProtocol-stubbed HTTP downloader.
/// Previously this manager had no dedicated test file (review bullet #11);
/// this coverage fixes that.
final class BfmeWorkshopSyncManagerTests: XCTestCase {
    private var sandbox: URL!
    private var installRoot: URL!
    private var originalDownloader: (@Sendable (String, String) async throws -> Void)!

    override func setUp() async throws {
        // Use a lowercase-only sandbox name. `ConfigUtils.getVirtualRegistry()`
        // lowercases install paths (to mirror Windows case-insensitive file
        // systems) which means the UUID must survive that transform.
        let uuidLower = UUID().uuidString.lowercased()
        sandbox = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bfme-sync-\(uuidLower)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)

        installRoot = sandbox.appendingPathComponent("install", isDirectory: true)
        try FileManager.default.createDirectory(at: installRoot, withIntermediateDirectories: true)

        BfmeRegistryManager.applicationSupportOverride = sandbox
        BfmeRegistryManager.applicationDataOverride = sandbox
        try await RegistryStore.shared.reset()

        // Point both BFME2 (game id 1) and RotWK (game id 2) at real disk
        // paths under the sandbox so `ConfigUtils.getVirtualRegistry()`
        // returns non-empty rows.
        let path = BfmeRegistryManager.softwarePath(forGame: 1)
        try await RegistryStore.shared.setValue(
            hive: .hklm, path: path, name: "InstallPath",
            value: .string(installRoot.path)
        )
        originalDownloader = BfmeWorkshopSyncManager.httpDownloader
    }

    override func tearDown() async throws {
        BfmeWorkshopSyncManager.httpDownloader = originalDownloader
        try await RegistryStore.shared.reset()
        BfmeRegistryManager.applicationSupportOverride = nil
        BfmeRegistryManager.applicationDataOverride = nil
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
    }

    /// A patch entry with a single http(s) file. The sync manager writes
    /// the active patch sidecar, invokes the downloader exactly once per
    /// file, and clears mod.txt at the end (type=0 is a patch, not a mod).
    func testSyncPatchRoutesFileThroughHttpDownloader() async throws {
        let recorder = DownloadRecorder()
        BfmeWorkshopSyncManager.httpDownloader = { url, path in
            recorder.append(url: url, path: path)
            try Data("payload".utf8).write(to: URL(fileURLWithPath: path))
        }

        // Seed ignoredGameFiles with one match so we also cover the skip.
        let entry = BfmeWorkshopEntry(
            guid: "patch-1",
            name: "Test Patch",
            version: "1.0",
            game: 1,
            type: 0,
            files: [
                BfmeWorkshopFile(name: "patch.big", url: "https://stub.local/patch.big"),
                BfmeWorkshopFile(name: "mod.txt", url: "https://stub.local/mod.txt") // ignored
            ]
        )

        try await BfmeWorkshopSyncManager.sync(entry)

        let downloaded = recorder.snapshot()
        XCTAssertEqual(downloaded.count, 1, "should skip ignored files")
        XCTAssertEqual(downloaded.first?.0, "https://stub.local/patch.big")
        // The downloader target must be inside the install directory.
        XCTAssertTrue(downloaded.first?.1.hasPrefix(installRoot.path) == true,
                      "downloader target should live under the install root: \(downloaded.first?.1 ?? "nil")")

        // active_patch_1.json was written.
        let activePatchURL = sandbox
            .appendingPathComponent("BFME Workshop")
            .appendingPathComponent("Config")
            .appendingPathComponent("active_patch_1.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: activePatchURL.path))

        // type=0 is a patch: mod.txt must not be left on disk.
        let modTxt = installRoot.appendingPathComponent("mod.txt").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: modTxt))
    }

    /// A mod entry (type=1) with a local file. The sync manager copies the
    /// local file into the install path and writes mod.txt pointing at the
    /// mod's destination directory.
    func testSyncModCopiesLocalFileAndWritesModTxt() async throws {
        // Seed a local source file that the sync manager will copy.
        let source = sandbox.appendingPathComponent("source.big")
        try Data("local-bytes".utf8).write(to: source)

        BfmeWorkshopSyncManager.httpDownloader = { _, _ in
            XCTFail("local file copies should not hit the downloader")
        }

        let entry = BfmeWorkshopEntry(
            guid: "mod-1",
            name: "Test Mod",
            version: "1.0",
            game: 1,
            type: 1,
            files: [BfmeWorkshopFile(name: "mod.big", url: source.path)]
        )
        try await BfmeWorkshopSyncManager.sync(entry)

        let copied = installRoot.appendingPathComponent("mod.big").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied))

        // mod.txt gets written for mod-type entries, pointing somewhere.
        let modTxt = installRoot.appendingPathComponent("mod.txt").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: modTxt),
                      "type=1 (mod) should leave a mod.txt sidecar")
    }

    /// An entry with a non-syncable type throws `packageNotSyncable`.
    func testSyncThrowsOnEnhancementOnlyType() async throws {
        let entry = BfmeWorkshopEntry(
            guid: "enh-only",
            name: "Snowy Palette",
            version: "1.0",
            game: 1,
            type: 5,
            files: []
        )
        do {
            try await BfmeWorkshopSyncManager.sync(entry)
            XCTFail("expected packageNotSyncable")
        } catch BfmeWorkshopError.packageNotSyncable {
            // success
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// A sync against a game with no install path throws `gameNotInstalled`.
    func testSyncThrowsWhenGameNotInstalled() async throws {
        // Clear the registry so the virtual-registry row is empty.
        try await RegistryStore.shared.reset()

        let entry = BfmeWorkshopEntry(
            guid: "patch-1",
            name: "Test Patch",
            version: "1.0",
            game: 0,
            type: 0,
            files: []
        )
        do {
            try await BfmeWorkshopSyncManager.sync(entry)
            XCTFail("expected gameNotInstalled")
        } catch BfmeWorkshopError.gameNotInstalled {
            // success
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

/// A thread-safe container for recording downloader invocations from
/// within `@Sendable` test closures. Plain `var` captures would warn under
/// Swift 6's sendable-capture rules.
final class DownloadRecorder: @unchecked Sendable {
    private var entries: [(String, String)] = []
    private let lock = NSLock()

    func append(url: String, path: String) {
        lock.lock(); defer { lock.unlock() }
        entries.append((url, path))
    }

    func snapshot() -> [(String, String)] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }
}
