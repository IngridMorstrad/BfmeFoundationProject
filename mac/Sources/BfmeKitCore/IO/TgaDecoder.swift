import Foundation

/// A decoded image as a row-major 8-bit-per-channel RGBA pixel buffer.
/// Platform-agnostic: the UI layer converts this to `CGImage`/`NSImage` on
/// macOS via a separate adapter.
public struct TgaImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Row-major RGBA pixels, `width * height * 4` bytes, top-to-bottom.
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// 1x1 transparent fallback used when the source image exceeds the
    /// original C# size guard (800x800).
    public static let placeholder = TgaImage(width: 1, height: 1, pixels: [0, 0, 0, 0])
}

public enum TgaDecoderError: Error {
    case truncated
    case unsupported(String)
}

public enum TgaDecoder {
    private static let headerSize = 18

    /// Decodes a Truevision TGA byte buffer into an RGBA pixel array. Supports
    /// type 2 (uncompressed true-color 24/32bpp) and type 10 (RLE true-color
    /// 24/32bpp). Other image types return a 1x1 transparent placeholder to
    /// match the original C# "not implemented" branches.
    public static func decode(_ image: Data) throws -> TgaImage {
        guard image.count >= headerSize else { throw TgaDecoderError.truncated }

        let idFieldLength = Int(image[image.startIndex + 0])
        let colorMapType = Int(image[image.startIndex + 1])
        let imageType = Int(image[image.startIndex + 2])
        // indexes 3..<12 describe the color map + origin; we don't need them
        // for the supported subset.
        let imageWidth = Int(image[image.startIndex + 13]) << 8 | Int(image[image.startIndex + 12])
        let imageHeight = Int(image[image.startIndex + 15]) << 8 | Int(image[image.startIndex + 14])
        let bitPerPixel = Int(image[image.startIndex + 16])
        let descriptor = Int(image[image.startIndex + 17])

        // Match the upstream 800x800 guard rail.
        if imageWidth > 800 || imageHeight > 800 {
            return .placeholder
        }

        guard imageWidth > 0, imageHeight > 0 else {
            return .placeholder
        }

        // Skip the id field before the color data.
        let payloadStart = image.startIndex + headerSize + idFieldLength
        guard payloadStart <= image.endIndex else { throw TgaDecoderError.truncated }
        let rawPayload = image.subdata(in: payloadStart..<image.endIndex)

        var colorData: [UInt8]
        if imageType == 10 { // RLE full-color
            colorData = try decodeRLE(rawPayload, bitPerPixel: bitPerPixel, width: imageWidth, height: imageHeight)
        } else if imageType == 2 { // uncompressed full-color
            colorData = [UInt8](rawPayload)
        } else {
            return .placeholder
        }

        guard colorMapType == 0 else { return .placeholder }

        let elementCount = bitPerPixel / 8
        guard elementCount == 3 || elementCount == 4 else { return .placeholder }

        var pixels = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)

        for y in 0..<imageHeight {
            for x in 0..<imageWidth {
                let sourceY = (descriptor & 0x20) == 0 ? (imageHeight - 1 - y) : y
                let sourceX = (descriptor & 0x10) == 0 ? x : (imageWidth - 1 - x)
                let sourceIndex = (sourceY * imageWidth + sourceX) * elementCount
                guard sourceIndex + elementCount <= colorData.count else {
                    // Gracefully stop on truncated buffers.
                    break
                }
                let b = colorData[sourceIndex + 0]
                let g = colorData[sourceIndex + 1]
                let r = colorData[sourceIndex + 2]
                let a: UInt8 = elementCount == 4 ? colorData[sourceIndex + 3] : 255
                let dest = (y * imageWidth + x) * 4
                pixels[dest + 0] = r
                pixels[dest + 1] = g
                pixels[dest + 2] = b
                pixels[dest + 3] = a
            }
        }

        return TgaImage(width: imageWidth, height: imageHeight, pixels: pixels)
    }

    private static func decodeRLE(_ source: Data, bitPerPixel: Int, width: Int, height: Int) throws -> [UInt8] {
        let elementCount = bitPerPixel / 8
        let decodeBufferLength = elementCount * width * height
        var decodeBuffer = [UInt8](repeating: 0, count: decodeBufferLength)
        var decoded = 0
        var offset = source.startIndex
        let end = source.endIndex

        while decoded < decodeBufferLength {
            guard offset < end else { throw TgaDecoderError.truncated }
            let packet = Int(source[offset])
            offset += 1
            if (packet & 0x80) != 0 {
                guard offset + elementCount <= end else { throw TgaDecoderError.truncated }
                var elements = [UInt8](repeating: 0, count: elementCount)
                for i in 0..<elementCount {
                    elements[i] = source[offset]
                    offset += 1
                }
                let count = (packet & 0x7F) + 1
                for _ in 0..<count {
                    guard decoded + elementCount <= decodeBufferLength else { break }
                    for j in 0..<elementCount {
                        decodeBuffer[decoded] = elements[j]
                        decoded += 1
                    }
                }
            } else {
                let count = (packet + 1) * elementCount
                guard offset + count <= end else { throw TgaDecoderError.truncated }
                for _ in 0..<count {
                    guard decoded < decodeBufferLength else { break }
                    decodeBuffer[decoded] = source[offset]
                    decoded += 1
                    offset += 1
                }
            }
        }
        return decodeBuffer
    }
}
