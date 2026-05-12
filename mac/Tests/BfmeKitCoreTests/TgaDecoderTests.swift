import XCTest
@testable import BfmeKitCore

final class TgaDecoderTests: XCTestCase {
    /// Builds an uncompressed 32-bpp top-left TGA with a known pixel pattern.
    private func makeUncompressedTga(width: Int, height: Int, pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)]) -> Data {
        precondition(pixels.count == width * height)
        var data = Data(count: 18)
        data[0] = 0                    // id field length
        data[1] = 0                    // no color map
        data[2] = 2                    // uncompressed true-color
        // color map spec (5 bytes) left zero
        // image origin x/y left zero
        data[12] = UInt8(width & 0xFF)
        data[13] = UInt8((width >> 8) & 0xFF)
        data[14] = UInt8(height & 0xFF)
        data[15] = UInt8((height >> 8) & 0xFF)
        data[16] = 32                  // bpp
        data[17] = 0x20                // top-left origin (bit 5 = 1)

        // TGA stores bytes as BGRA.
        for p in pixels {
            data.append(contentsOf: [p.b, p.g, p.r, p.a])
        }
        return data
    }

    func testDecodeUncompressed2x2RoundTrip() throws {
        let reference: [(UInt8, UInt8, UInt8, UInt8)] = [
            (255, 0, 0, 255),   // red
            (0, 255, 0, 200),   // green + alpha
            (0, 0, 255, 255),   // blue
            (10, 20, 30, 40)    // quirk
        ]
        let tgaBytes = makeUncompressedTga(width: 2, height: 2, pixels: reference)
        let image = try TgaDecoder.decode(tgaBytes)
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 2)
        XCTAssertEqual(image.pixels.count, 2 * 2 * 4)
        for (i, expected) in reference.enumerated() {
            XCTAssertEqual(image.pixels[i * 4 + 0], expected.0)
            XCTAssertEqual(image.pixels[i * 4 + 1], expected.1)
            XCTAssertEqual(image.pixels[i * 4 + 2], expected.2)
            XCTAssertEqual(image.pixels[i * 4 + 3], expected.3)
        }
    }

    func testOversizedImageReturnsPlaceholder() throws {
        var data = Data(count: 18)
        data[2] = 2
        data[12] = UInt8(801 & 0xFF)
        data[13] = UInt8((801 >> 8) & 0xFF)
        data[14] = UInt8(10 & 0xFF)
        data[15] = UInt8((10 >> 8) & 0xFF)
        data[16] = 32
        let image = try TgaDecoder.decode(data)
        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 1)
    }
}
