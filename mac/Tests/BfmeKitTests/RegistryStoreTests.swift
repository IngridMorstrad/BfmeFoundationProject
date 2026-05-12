import XCTest
@testable import BfmeKit
import BfmeKitCore

final class RegistryStoreTests: XCTestCase {
    private var sandbox: URL!

    override func setUp() async throws {
        sandbox = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bfme-regstore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        RegistryStore.applicationSupportOverride = sandbox
        try await RegistryStore.shared.reset()
    }

    override func tearDown() async throws {
        try await RegistryStore.shared.reset()
        RegistryStore.applicationSupportOverride = nil
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
    }

    func testRoundTripStringValue() async throws {
        let store = RegistryStore.shared
        let path = #"SOFTWARE\Electronic Arts\EA Games\The Battle for Middle-earth"#
        try await store.setValue(hive: .hklm, path: path, name: "InstallPath", value: .string("/Users/test/BFME"))
        let read = await store.getValue(hive: .hklm, path: path, name: "InstallPath")
        XCTAssertEqual(read, .string("/Users/test/BFME"))
    }

    func testCreateSubKeyThenOpen() async throws {
        let store = RegistryStore.shared
        let path = #"SOFTWARE\Electronic Arts"#
        let initial = await store.openSubKey(hive: .hklm, path: path)
        XCTAssertFalse(initial)
        try await store.createSubKey(hive: .hklm, path: path)
        let afterCreate = await store.openSubKey(hive: .hklm, path: path)
        XCTAssertTrue(afterCreate)
    }

    func testSetValueDifferentTypes() async throws {
        let store = RegistryStore.shared
        let path = #"SOFTWARE\Test"#
        try await store.setValue(hive: .hklm, path: path, name: "Str", value: .string("hello"))
        try await store.setValue(hive: .hklm, path: path, name: "Int", value: .dword(65539))
        try await store.setValue(hive: .hklm, path: path, name: "Bin", value: .binary(Data([0xDE, 0xAD, 0xBE, 0xEF])))
        try await store.setValue(hive: .hklm, path: path, name: "Multi", value: .multiString(["a", "b", "c"]))

        let str = await store.getValue(hive: .hklm, path: path, name: "Str")
        let int = await store.getValue(hive: .hklm, path: path, name: "Int")
        let bin = await store.getValue(hive: .hklm, path: path, name: "Bin")
        let multi = await store.getValue(hive: .hklm, path: path, name: "Multi")

        XCTAssertEqual(str, .string("hello"))
        XCTAssertEqual(int, .dword(65539))
        XCTAssertEqual(bin, .binary(Data([0xDE, 0xAD, 0xBE, 0xEF])))
        XCTAssertEqual(multi, .multiString(["a", "b", "c"]))
    }

    func testDeleteSubKeyTreeRemovesNestedKeys() async throws {
        let store = RegistryStore.shared
        try await store.setValue(hive: .hklm, path: #"SOFTWARE\Test"#, name: "a", value: .string("1"))
        try await store.setValue(hive: .hklm, path: #"SOFTWARE\Test\Child"#, name: "a", value: .string("2"))
        try await store.setValue(hive: .hklm, path: #"SOFTWARE\Test\Child\Leaf"#, name: "a", value: .string("3"))
        try await store.setValue(hive: .hklm, path: #"SOFTWARE\Other"#, name: "a", value: .string("99"))

        try await store.deleteSubKeyTree(hive: .hklm, path: #"SOFTWARE\Test"#)

        let hasTest = await store.openSubKey(hive: .hklm, path: #"SOFTWARE\Test"#)
        let hasChild = await store.openSubKey(hive: .hklm, path: #"SOFTWARE\Test\Child"#)
        let hasLeaf = await store.openSubKey(hive: .hklm, path: #"SOFTWARE\Test\Child\Leaf"#)
        let hasOther = await store.openSubKey(hive: .hklm, path: #"SOFTWARE\Other"#)

        XCTAssertFalse(hasTest)
        XCTAssertFalse(hasChild)
        XCTAssertFalse(hasLeaf)
        XCTAssertTrue(hasOther)
    }

    func testPersistsToDiskAtomicallyAndLeavesNoTempFile() async throws {
        let store = RegistryStore.shared
        try await store.setValue(hive: .hklm, path: #"SOFTWARE\Test"#, name: "k", value: .string("v"))

        let url = RegistryStore.storeURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Foundation's `.atomic` write stages a temp sibling; after a successful
        // write the temp file must be gone.
        let dir = url.deletingLastPathComponent()
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let tempFiles = siblings.filter { $0 != "registry.json" }
        XCTAssertTrue(tempFiles.isEmpty, "atomic write must not leave temp files behind, found: \(tempFiles)")

        // JSON is valid and round-trips through a fresh decoder.
        let data = try Data(contentsOf: url)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed)
        let hklm = parsed?["hklm"] as? [String: Any]
        XCTAssertNotNil(hklm?["SOFTWARE\\Test"])
    }

    func testNormalizeIsAppliedToPaths() async throws {
        let store = RegistryStore.shared
        try await store.setValue(hive: .hklm, path: #"\SOFTWARE\Normalize\\"#, name: "k", value: .string("v"))
        let hasKey = await store.openSubKey(hive: .hklm, path: #"SOFTWARE\Normalize"#)
        XCTAssertTrue(hasKey)
        let value = await store.getValue(hive: .hklm, path: #"SOFTWARE/Normalize"#, name: "k")
        XCTAssertEqual(value, .string("v"))
    }
}
