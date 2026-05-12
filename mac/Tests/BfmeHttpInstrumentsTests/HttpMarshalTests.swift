import XCTest
@testable import BfmeHttpInstruments

final class HttpMarshalTests: XCTestCase {
    func testB64GzipRoundTripMatchesOriginal() throws {
        let original = "BFME Workshop response body with unicode: Rohan, Mordor, Isengard ✨"
        let encoded = try HttpMarshal.encodeB64Gzip(original)
        // base64-encoded output must round-trip through the decoder.
        let decoded = try HttpMarshal.decodeB64Gzip(encoded)
        XCTAssertEqual(decoded, original)
    }

    func testGzipDecoderRejectsBadBase64() {
        XCTAssertThrowsError(try HttpMarshal.decodeB64Gzip("not valid base64 !!!"))
    }

    func testGzipDecoderRejectsShortPayload() {
        // Four bytes of zero base64 encoded -> length prefix but no gzip.
        let payload = Data([0, 0, 0, 0]).base64EncodedString()
        XCTAssertThrowsError(try HttpMarshal.decodeB64Gzip(payload))
    }

    func testGzipDecompressRejectsNonGzipGarbage() {
        // 32 bytes of non-gzip garbage. zlib's inflate should report
        // Z_DATA_ERROR because the header does not match either the gzip or
        // zlib format, and there is no way to interpret it as a valid stream.
        let bogus = Data([UInt8](repeating: 0x7F, count: 32))
        XCTAssertThrowsError(try GzipDecoder.decompress(bogus))
    }

    func testGzipRoundTripPreservesBinaryPayload() throws {
        let bytes = Data((0..<1024).map { UInt8($0 % 256) })
        let compressed = try GzipDecoder.compress(bytes)
        XCTAssertNotEqual(compressed, bytes)
        let decompressed = try GzipDecoder.decompress(compressed)
        XCTAssertEqual(decompressed, bytes)
    }

    func testMalformedUrlSurfacesDecodeError() async {
        do {
            _ = try await HttpMarshal.getString(url: "not a real url://bad")
            XCTFail("expected failure")
        } catch let error as HttpMarshalError {
            switch error {
            case .requestFailed, .decodeFailed:
                break // expected
            default:
                XCTFail("unexpected error: \(error)")
            }
        } catch {
            // Any swift error is acceptable; we only assert a throw.
        }
    }
}
