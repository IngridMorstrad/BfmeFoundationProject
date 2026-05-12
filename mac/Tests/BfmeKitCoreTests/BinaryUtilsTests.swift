import XCTest
@testable import BfmeKitCore

final class BinaryUtilsTests: XCTestCase {
    func testReadUInt32LittleAndBigEndian() throws {
        // Bytes: 0x78 0x56 0x34 0x12 0xAA 0xBB 0xCC 0xDD
        let bytes = Data([0x78, 0x56, 0x34, 0x12, 0xAA, 0xBB, 0xCC, 0xDD])
        var reader = BinaryReader(bytes)
        XCTAssertEqual(try reader.readUInt32LE(), 0x12345678)
        XCTAssertEqual(try reader.readUInt32BE(), 0xAABBCCDD)
    }

    func testWriteUInt32RoundTrip() throws {
        let le = BinaryUtils.writeUInt32LE(0xCAFEBABE)
        XCTAssertEqual([UInt8](le), [0xBE, 0xBA, 0xFE, 0xCA])

        let be = BinaryUtils.writeUInt32BE(0xCAFEBABE)
        XCTAssertEqual([UInt8](be), [0xCA, 0xFE, 0xBA, 0xBE])
    }

    func testReadNullTerminatedString() throws {
        var data = Data("hello".utf8)
        data.append(0)
        data.append(Data("world".utf8))
        data.append(0)
        var reader = BinaryReader(data)
        XCTAssertEqual(try reader.readNullTerminatedString(), "hello")
        XCTAssertEqual(try reader.readNullTerminatedString(), "world")
    }

    func testReadFixedLengthString() throws {
        var reader = BinaryReader(Data("BIGF".utf8))
        XCTAssertEqual(try reader.readFixedLengthString(4), "BIGF")
    }

    func testReadFixedLengthStringUnicodeCsfInverted() throws {
        // "Hi" as UTF-16LE is [0x48, 0x00, 0x69, 0x00]. CSF inverts every byte.
        let inverted = Data([0x48, 0x00, 0x69, 0x00].map { ~$0 })
        var reader = BinaryReader(inverted)
        let decoded = try reader.readFixedLengthStringUnicode(2)
        XCTAssertEqual(decoded, "Hi")
    }

    func testReadingPastEndThrows() {
        var reader = BinaryReader(Data([0x01, 0x02]))
        XCTAssertThrowsError(try reader.readUInt32LE())
    }
}
