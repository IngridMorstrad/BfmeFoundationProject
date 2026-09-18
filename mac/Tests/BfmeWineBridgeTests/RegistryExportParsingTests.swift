import XCTest
@testable import BfmeWineBridge

/// Covers parsing of the `.reg` documents `regedit /E` produces, which is how
/// values are read back out of a prefix.
final class RegistryExportParsingTests: XCTestCase {
    private let keyPath = #"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Electronic Arts\Electronic Arts\The Battle for Middle-earth II"#

    private func export(_ body: String) -> Data {
        let text = "Windows Registry Editor Version 5.00\r\n\r\n" + body
        var data = Data([0xFF, 0xFE])
        for unit in Array(text.utf16) {
            data.append(UInt8(unit & 0xFF))
            data.append(UInt8(unit >> 8))
        }
        return data
    }

    // MARK: - Encoding

    func testDecodesUtf16LittleEndianWithBom() {
        let data = export("[\(keyPath)]\r\n\"InstallPath\"=\"Z:\\\\g\\\\\"\r\n")
        let values = WinePrefixBridge.parseExport(data, forKeyPath: keyPath)
        XCTAssertEqual(values?["InstallPath"], .string(#"Z:\g\"#))
    }

    func testNonAsciiValueRoundTripsThroughUtf16() {
        // The reason readback uses regedit /E instead of reg query: reg.exe
        // emits the OEM codepage and mangles this.
        let data = export("[\(keyPath)]\r\n\"InstallPath\"=\"Z:\\\\Users\\\\José\\\\BFME2\\\\\"\r\n")
        let values = WinePrefixBridge.parseExport(data, forKeyPath: keyPath)
        XCTAssertEqual(values?["InstallPath"], .string(#"Z:\Users\José\BFME2\"#))
    }

    func testFallsBackToUtf8WhenNoBomPresent() {
        let text = "Windows Registry Editor Version 5.00\r\n\r\n[\(keyPath)]\r\n\"Language\"=\"English\"\r\n"
        let values = WinePrefixBridge.parseExport(Data(text.utf8), forKeyPath: keyPath)
        XCTAssertEqual(values?["Language"], .string("English"))
    }

    // MARK: - Round trip against our own writer

    func testRoundTripsDocumentsProducedByRegistryDocument() {
        // Whatever we can write, we must be able to read back.
        var document = RegistryDocument()
        document.add(RegistryKeyEntry(hive: .localMachine, path: #"SOFTWARE\RT"#, values: [
            (name: "InstallPath", value: .string(#"Z:\Users\me\My Games\BFME 2\"#)),
            (name: "Quoted", value: .string(#"a "b" c"#)),
            (name: "Version", value: .dword(65539)),
            (name: "", value: .string("default-value"))
        ]))

        let values = WinePrefixBridge.parseExport(
            document.serializedData(),
            forKeyPath: #"HKEY_LOCAL_MACHINE\SOFTWARE\RT"#
        )

        XCTAssertEqual(values?["InstallPath"], .string(#"Z:\Users\me\My Games\BFME 2\"#))
        XCTAssertEqual(values?["Quoted"], .string(#"a "b" c"#))
        XCTAssertEqual(values?["Version"], .dword(65539))
        XCTAssertEqual(values?[""], .string("default-value"))
    }

    // MARK: - Section matching

    func testReturnsNilWhenTheRequestedKeyIsAbsentFromTheExport() {
        let data = export("[HKEY_LOCAL_MACHINE\\SOFTWARE\\Other]\r\n\"X\"=\"y\"\r\n")
        XCTAssertNil(WinePrefixBridge.parseExport(data, forKeyPath: keyPath))
    }

    func testDoesNotLeakValuesFromSubkeysIntoTheParentKey() {
        // regedit /E exports the key plus every subkey, so section matching has
        // to be exact. The serial in \ergc must not appear on the game key.
        let data = export("""
        [\(keyPath)]\r
        "InstallPath"="Z:\\\\g\\\\"\r
        \r
        [\(keyPath)\\ergc]\r
        @="SERIAL1234"\r
        """)

        let gameKey = WinePrefixBridge.parseExport(data, forKeyPath: keyPath)
        XCTAssertEqual(gameKey?["InstallPath"], .string(#"Z:\g\"#))
        XCTAssertNil(gameKey?[""], "the subkey's default value leaked into the parent")

        let ergc = WinePrefixBridge.parseExport(data, forKeyPath: keyPath + #"\ergc"#)
        XCTAssertEqual(ergc?[""], .string("SERIAL1234"))
    }

    func testMatchesSectionCaseInsensitively() {
        // Registry paths are case insensitive; regedit may not echo our casing.
        let data = export("[HKEY_LOCAL_MACHINE\\software\\Test]\r\n\"A\"=\"b\"\r\n")
        XCTAssertEqual(
            WinePrefixBridge.parseExport(data, forKeyPath: #"HKEY_LOCAL_MACHINE\SOFTWARE\Test"#)?["A"],
            .string("b")
        )
    }

    func testEmptyKeyWithNoValuesParsesAsPresentButEmpty() {
        let data = export("[\(keyPath)]\r\n")
        XCTAssertEqual(WinePrefixBridge.parseExport(data, forKeyPath: keyPath), [:])
    }

    // MARK: - Value line parsing

    func testParsesDwordAsTypedValueNotHexString() {
        let parsed = WinePrefixBridge.parseValueLine("\"Version\"=dword:00010003")
        XCTAssertEqual(parsed?.value, .dword(65539))
    }

    func testParsesDefaultValueSyntax() {
        let parsed = WinePrefixBridge.parseValueLine("@=\"ABCDEF\"")
        XCTAssertEqual(parsed?.name, "")
        XCTAssertEqual(parsed?.value, .string("ABCDEF"))
    }

    func testParsesValueContainingSpaces() {
        let parsed = WinePrefixBridge.parseValueLine("\"UserDataLeafName\"=\"My Battle for Middle-earth II Files\"")
        XCTAssertEqual(parsed?.value, .string("My Battle for Middle-earth II Files"))
    }

    func testParsesValueNameContainingASpace() {
        let parsed = WinePrefixBridge.parseValueLine("\"Game Registry\"=\"SOFTWARE\\\\EA\"")
        XCTAssertEqual(parsed?.name, "Game Registry")
        XCTAssertEqual(parsed?.value, .string(#"SOFTWARE\EA"#))
    }

    func testRejectsMalformedLines() {
        XCTAssertNil(WinePrefixBridge.parseValueLine("not a value line"))
        XCTAssertNil(WinePrefixBridge.parseValueLine("\"Unterminated=\"x\""))
        XCTAssertNil(WinePrefixBridge.parseValueLine("\"Name\"=dword:zzzz"))
    }

    func testUnescapeReversesEscape() {
        for original in [#"Z:\Users\me\"#, #"a "b" c"#, #"back\\slash"#, "plain"] {
            XCTAssertEqual(
                WinePrefixBridge.unescape(RegistryDocument.escape(original)),
                original,
                "failed to round trip \(original)"
            )
        }
    }
}
