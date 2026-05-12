import XCTest
@testable import BfmeKitCore

final class BigArchiveReaderTests: XCTestCase {
    /// Builds a minimal but real BIGF archive: 4-byte id, 4 bytes little-endian
    /// total size, 4 bytes big-endian file count, 4 bytes big-endian index
    /// table size, then N index entries (offset BE, size BE, null-terminated
    /// name), followed by each file's payload at the declared offset.
    func testRoundTripTwoFiles() throws {
        let file1Name = "data/greeting.txt"
        let file1Data = Data("hello bfme".utf8)
        let file2Name = "readme.txt"
        let file2Data = Data("second file".utf8)

        // Build index entries first so we know their total size.
        func indexEntry(offset: UInt32, size: UInt32, name: String) -> Data {
            var entry = Data()
            entry.append(BinaryUtils.writeUInt32BE(offset))
            entry.append(BinaryUtils.writeUInt32BE(size))
            entry.append(Data(name.utf8))
            entry.append(0)
            return entry
        }

        // Layout:
        //   header 16 bytes + index entries
        //   payload starts immediately after the index.
        let headerSize = 16
        // Build index first with placeholder offsets then rewrite.
        var index1 = indexEntry(offset: 0, size: UInt32(file1Data.count), name: file1Name)
        var index2 = indexEntry(offset: 0, size: UInt32(file2Data.count), name: file2Name)

        let indexSize = index1.count + index2.count
        let file1Offset = UInt32(headerSize + indexSize)
        let file2Offset = file1Offset + UInt32(file1Data.count)

        index1 = indexEntry(offset: file1Offset, size: UInt32(file1Data.count), name: file1Name)
        index2 = indexEntry(offset: file2Offset, size: UInt32(file2Data.count), name: file2Name)

        let totalSize = UInt32(headerSize + indexSize + file1Data.count + file2Data.count)

        var archive = Data()
        archive.append(Data("BIGF".utf8))
        archive.append(BinaryUtils.writeUInt32LE(totalSize))
        archive.append(BinaryUtils.writeUInt32BE(2))
        archive.append(BinaryUtils.writeUInt32BE(UInt32(indexSize)))
        archive.append(index1)
        archive.append(index2)
        archive.append(file1Data)
        archive.append(file2Data)

        // Write to a temp file and round-trip through the reader.
        let tempFile = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bfme-big-\(UUID().uuidString).big")
        try archive.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let entries = try BigArchiveReader.unpack(tempFile.path)
        XCTAssertEqual(entries.count, 2)

        let greeting = try XCTUnwrap(entries[file1Name.lowercased()])
        let readme = try XCTUnwrap(entries[file2Name.lowercased()])
        XCTAssertEqual(try greeting.getData(), file1Data)
        XCTAssertEqual(try readme.getData(), file2Data)
    }

    func testDecodeStringReplacesEscapes() {
        let decoded = BigArchiveReader.decodeString("my_20map_2Ebig_3A_5Cthingy")
        XCTAssertEqual(decoded, #"my map.big:\thingy"#)
    }

    func testUnpackMissingFileReturnsEmptyByDefault() throws {
        let missing = "/tmp/definitely-not-a-real-archive-\(UUID().uuidString).big"
        let result = try BigArchiveReader.unpack(missing)
        XCTAssertTrue(result.isEmpty)
    }
}
