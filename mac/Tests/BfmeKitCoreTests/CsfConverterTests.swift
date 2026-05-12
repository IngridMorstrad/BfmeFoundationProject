import XCTest
@testable import BfmeKitCore

final class CsfConverterTests: XCTestCase {
    /// Builds a one-label CSF payload with a single string value. The format:
    /// header "CSF " + UInt32LE version + UInt32LE labels + UInt32LE strings +
    /// UInt32LE extraTag + UInt32LE lang; then per label:
    ///   "LBL " + UInt32LE pairs + UInt32LE nameLength + name bytes;
    /// and per pair:
    ///   "STR " + UInt32LE valueLength(utf16 units) + (inverted utf16le bytes).
    private func makeSingleEntryCsf(name: String, value: String) -> Data {
        var data = Data()
        data.append(Data("CSF ".utf8))
        data.append(BinaryUtils.writeUInt32LE(3))     // version
        data.append(BinaryUtils.writeUInt32LE(1))     // labels
        data.append(BinaryUtils.writeUInt32LE(1))     // strings
        data.append(BinaryUtils.writeUInt32LE(0))     // extra tag
        data.append(BinaryUtils.writeUInt32LE(0))     // lang

        data.append(Data("LBL ".utf8))
        data.append(BinaryUtils.writeUInt32LE(1))     // pairs
        let nameBytes = Data(name.utf8)
        data.append(BinaryUtils.writeUInt32LE(UInt32(nameBytes.count)))
        data.append(nameBytes)

        data.append(Data("STR ".utf8))
        let utf16Units = Array(value.utf16)
        data.append(BinaryUtils.writeUInt32LE(UInt32(utf16Units.count)))
        for unit in utf16Units {
            let low = UInt8(unit & 0xFF)
            let high = UInt8((unit >> 8) & 0xFF)
            data.append(~low)
            data.append(~high)
        }
        return data
    }

    func testConvertSingleEntry() throws {
        let payload = makeSingleEntryCsf(name: "GUI:Hello", value: "Greetings!")
        let str = try CsfConverter.convertToStr(payload)
        XCTAssertTrue(str.contains("GUI:Hello"))
        XCTAssertTrue(str.contains("\"Greetings!\""))
        XCTAssertTrue(str.contains("END"))
    }

    func testNewlinesInValuesAreEscaped() throws {
        let payload = makeSingleEntryCsf(name: "GUI:Multi", value: "a\nb")
        let str = try CsfConverter.convertToStr(payload)
        XCTAssertTrue(str.contains("\"a\\nb\""))
    }

    func testEmptyPayloadReturnsEmpty() throws {
        let str = try CsfConverter.convertToStr(Data())
        XCTAssertEqual(str, "")
    }
}
