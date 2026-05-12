import XCTest
@testable import BfmeWorkshopKit
import BfmeKit
import BfmeKitCore

final class BfmeWorkshopScriptManagerTests: XCTestCase {
    private var sandbox: URL!

    override func setUp() async throws {
        sandbox = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bfme-wps-\(UUID().uuidString)", isDirectory: true)
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

    /// The headline end-to-end flow: a script reads a real registry value,
    /// binds it to a variable, then a `require` line interpolates that
    /// variable and asserts it is non-empty. Paths with spaces are quoted
    /// so the tokenizer sees them as a single token (the quote stripping
    /// preserves the leading `HKLM\` marker).
    func testLetFromHklmThenRequireIfNotEmpty() async throws {
        let path = #"SOFTWARE\WOW6432Node\Electronic Arts\EA Games\The Battle for Middle-earth"#
        try await RegistryStore.shared.setValue(
            hive: .hklm, path: path, name: "InstallPath",
            value: .string(#"C:\Games\BFME"#)
        )

        let source = """
        let InstallPath be InstallPath from "HKLM\\SOFTWARE\\Electronic Arts\\EA Games\\The Battle for Middle-earth"
        require "HasInstall" if "{InstallPath}" !equals ""
        """

        let result = try await BfmeWorkshopScriptManager.run(source)
        XCTAssertEqual(result.variables["InstallPath"], #"C:\Games\BFME"#)
        // `require ... if` flips the flag to `false` on a passing comparison
        // (mirrors the double-negative in the C# reference).
        XCTAssertEqual(result.requirements["HasInstall"], false)
    }

    func testLetAllFromHklmEnumeratesEveryValue() async throws {
        let path = #"SOFTWARE\WOW6432Node\Foo"#
        try await RegistryStore.shared.setValue(
            hive: .hklm, path: path, name: "A", value: .string("1"))
        try await RegistryStore.shared.setValue(
            hive: .hklm, path: path, name: "B", value: .string("2"))

        let source = "let All be all from \"HKLM\\SOFTWARE\\Foo\""
        let result = try await BfmeWorkshopScriptManager.run(source)
        let text = try XCTUnwrap(result.variables["All"])
        XCTAssertTrue(text.contains("A = 1"), "expected 'A = 1' in \(text)")
        XCTAssertTrue(text.contains("B = 2"), "expected 'B = 2' in \(text)")
    }

    func testRequireFailsIfComparisonFails() async throws {
        // Comparison fails => requirement is marked "needs action" (true).
        let source = "require \"NeedsBfme2\" if \"foo\" equals \"bar\""
        let result = try await BfmeWorkshopScriptManager.run(source)
        XCTAssertEqual(result.requirements["NeedsBfme2"], true)
    }

    func testFilesAndPrintDirectives() async throws {
        let source = """
        files be from "some/path"
        print "hello"
        """
        let result = try await BfmeWorkshopScriptManager.run(source)
        XCTAssertEqual(result.filesDirectory, "some/path")
    }

    func testSyntaxErrorIncludesLineNumber() async {
        let source = "let X"
        do {
            _ = try await BfmeWorkshopScriptManager.run(source)
            XCTFail("Expected syntax error")
        } catch let BfmeWorkshopError.scriptSyntaxError(msg) {
            XCTAssertTrue(msg.contains("line 1"), "message should reference line number: \(msg)")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testReadIniFileFromAbsolutePath() async throws {
        let iniURL = sandbox.appendingPathComponent("settings.ini")
        try "Version=1.0.3\nLanguage=english".write(to: iniURL, atomically: true, encoding: .utf8)

        let source = "let Ver be Version from \"\(iniURL.path)\""
        let result = try await BfmeWorkshopScriptManager.run(source)
        XCTAssertEqual(result.variables["Ver"], "1.0.3")
    }

    func testCommentLinesAreSkipped() async throws {
        let source = """
        // This is a comment
        let X be "value"
        """
        let result = try await BfmeWorkshopScriptManager.run(source)
        XCTAssertEqual(result.variables["X"], "value")
    }
}
