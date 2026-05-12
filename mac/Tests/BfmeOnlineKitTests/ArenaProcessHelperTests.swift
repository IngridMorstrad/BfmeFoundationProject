import XCTest
@testable import BfmeOnlineKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Review-v2 #4: the arena child is spawned with `--pipe-name <path>` and
/// must have a readable endpoint at that path BEFORE `Process.run`, so
/// the child's connect() does not hang. These tests cover the pipe-create
/// contract without actually spawning a binary (spawning arena on Linux CI
/// is impossible: it's a Wine-hosted Windows exe).
final class ArenaProcessHelperTests: XCTestCase {
    func testCreatePipeEndpointCreatesFifoOnDisk() throws {
        let uuid = UUID().uuidString
        let path = try ArenaProcessHelper.createPipeEndpoint(uuid: uuid)
        defer { unlink(path) }
        XCTAssertTrue(path.hasSuffix("/bfme-arena-\(uuid).sock"))

        var st = stat()
        let result = path.withCString { cString in
            stat(cString, &st)
        }
        XCTAssertEqual(result, 0, "pipe file should exist at \(path)")
        let mode = st.st_mode
        // S_ISFIFO: the endpoint is a FIFO, not a regular file.
        let isFifo = (mode & S_IFMT) == S_IFIFO
        XCTAssertTrue(isFifo, "endpoint at \(path) should be a FIFO, mode=\(mode)")
    }

    func testCreatePipeEndpointRecreatesAtomicallyWhenStaleExists() throws {
        let uuid = UUID().uuidString
        let dir = NSTemporaryDirectory()
        let stalePath = "\(dir.hasSuffix("/") ? String(dir.dropLast()) : dir)/bfme-arena-\(uuid).sock"
        // Drop a regular file at the pipe's path to simulate a stale
        // endpoint the previous run left behind.
        try Data("stale".utf8).write(to: URL(fileURLWithPath: stalePath))

        let path = try ArenaProcessHelper.createPipeEndpoint(uuid: uuid)
        defer { unlink(path) }
        XCTAssertEqual(path, stalePath)

        var st = stat()
        XCTAssertEqual(path.withCString { stat($0, &st) }, 0)
        XCTAssertEqual(st.st_mode & S_IFMT, S_IFIFO, "stale file should have been replaced with a FIFO")
    }

    func testCreatePipeEndpointReturnsUniquePathsForDistinctUUIDs() throws {
        let a = try ArenaProcessHelper.createPipeEndpoint()
        defer { unlink(a) }
        let b = try ArenaProcessHelper.createPipeEndpoint()
        defer { unlink(b) }
        XCTAssertNotEqual(a, b)
    }
}
