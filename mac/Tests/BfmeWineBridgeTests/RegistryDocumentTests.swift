import XCTest
@testable import BfmeWineBridge

final class RegistryDocumentTests: XCTestCase {
    func testSerializesHeaderAndCRLFLineEndings() {
        var document = RegistryDocument()
        document.add(RegistryKeyEntry(hive: .localMachine, path: #"SOFTWARE\Test"#, values: [
            (name: "Name", value: .string("value"))
        ]))

        let text = document.serialize()

        XCTAssertTrue(text.hasPrefix("Windows Registry Editor Version 5.00\r\n\r\n"))
        XCTAssertTrue(text.contains("[HKEY_LOCAL_MACHINE\\SOFTWARE\\Test]\r\n"))
        XCTAssertTrue(text.contains("\"Name\"=\"value\"\r\n"))
        XCTAssertFalse(text.contains("\n\n"), "line endings must be CRLF, not bare LF")
    }

    func testEscapesBackslashesInPathValues() {
        var document = RegistryDocument()
        document.add(RegistryKeyEntry(hive: .localMachine, path: #"SOFTWARE\Test"#, values: [
            (name: "InstallPath", value: .string(#"Z:\Users\me\BFME2\"#))
        ]))

        // A Windows path must survive as doubled backslashes or regedit
        // interprets them as escapes and silently mangles the value.
        XCTAssertTrue(document.serialize().contains(#""InstallPath"="Z:\\Users\\me\\BFME2\\""#))
    }

    func testEscapesEmbeddedQuotes() {
        XCTAssertEqual(RegistryDocument.escape(#"a"b"#), #"a\"b"#)
    }

    func testEscapesBackslashBeforeQuote() {
        // Ordering bug bait: escaping quotes first would turn \" into \\" and
        // then the backslash pass would produce \\\", which is wrong.
        XCTAssertEqual(RegistryDocument.escape(#"a\"b"#), #"a\\\"b"#)
    }

    func testDwordIsEightLowercaseHexDigits() {
        var document = RegistryDocument()
        document.add(RegistryKeyEntry(hive: .localMachine, path: "SOFTWARE\\Test", values: [
            (name: "Version", value: .dword(65539)),
            (name: "Restart", value: .dword(0))
        ]))

        let text = document.serialize()
        XCTAssertTrue(text.contains("\"Version\"=dword:00010003"))
        XCTAssertTrue(text.contains("\"Restart\"=dword:00000000"))
    }

    func testEmptyValueNameBecomesDefaultValueSyntax() {
        var document = RegistryDocument()
        document.add(RegistryKeyEntry(hive: .localMachine, path: #"SOFTWARE\Test\ergc"#, values: [
            (name: "", value: .string("ABC123"))
        ]))

        XCTAssertTrue(document.serialize().contains("@=\"ABC123\""))
    }

    func testSerializedDataIsUtf16LittleEndianWithBom() {
        var document = RegistryDocument()
        document.add(RegistryKeyEntry(hive: .localMachine, path: "SOFTWARE\\T", values: [
            (name: "N", value: .string("v"))
        ]))

        let data = document.serializedData()

        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xFE], "missing UTF-16LE BOM")
        // 'W' of "Windows" must be the next unit, low byte first.
        XCTAssertEqual(Array(data.dropFirst(2).prefix(2)), [0x57, 0x00])

        let decoded = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        XCTAssertEqual(decoded, document.serialize())
    }

    func testNonAsciiPathSurvivesEncoding() {
        // The reason for choosing the Unicode .reg format: a macOS account
        // name with an accent must round trip.
        var document = RegistryDocument()
        document.add(RegistryKeyEntry(hive: .localMachine, path: "SOFTWARE\\T", values: [
            (name: "InstallPath", value: .string(#"Z:\Users\Bilbó\BFME\"#))
        ]))

        let data = document.serializedData()
        let decoded = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        XCTAssertEqual(decoded?.contains("Bilbó"), true)
    }

    func testEmptyDocumentSerializesToHeaderOnly() {
        XCTAssertTrue(RegistryDocument().isEmpty)
        XCTAssertEqual(RegistryDocument().serialize(), "Windows Registry Editor Version 5.00\r\n\r\n")
    }
}
