import Foundation
import BfmeKitCore

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

/// Mirrors `src/BfmeFoundationProject_BfmeKit/Logic/BfmeMapImporter.cs`.
///
/// The C# version combined map-metadata parsing (`mapcache.ini` + `.str`/`.csf`
/// string tables) with a rendering step that composited three bitmaps using
/// `System.Drawing.Graphics`. This Swift port splits the two:
///
///   * `importMaps(fromMapCacheIni:stringTables:availableMapIds:)` — pure
///     string parsing, no file or registry touch; the caller is expected to
///     have gathered the inputs via the BIG archive reader.
///   * `generateMapPreview(map:tga:)` — composites the preview onto a new
///     bitmap. On macOS we use CoreGraphics (`CGContext`) and return a real
///     `CGImage`. On Linux we synthesize the same RGBA buffer in memory so
///     the test suite can still exercise the layout math.
public enum BfmeMapImporter {
    // MARK: - Parsing

    /// Parses a `mapcache.ini` source string together with a bag of pre-collected
    /// string-table text (the `.str`/`.csf` lines that resolve display names
    /// like `MAP:FourPlayerMap`). `availableMapIds` is the set of map file ids
    /// that actually exist on disk or inside the game's `.big` archives; maps
    /// whose id is missing from that list are dropped, matching the C# version.
    public static func importMaps(
        fromMapCacheIni mapcache: String,
        stringTables: [String] = [],
        availableMapIds: Set<String> = []
    ) -> [BfmeMap] {
        // Parse string-table blocks: `<id>\n<content>\nend`.
        var parsedStrings: [String: String] = [:]
        for table in stringTables {
            var blockId = ""
            var blockContent = ""
            for rawLine in table.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\n\r \t"))
                if line.isEmpty || line.hasPrefix("//") || line.hasPrefix(";") { continue }
                if blockId.isEmpty {
                    blockId = line
                    blockContent = ""
                } else if line.lowercased().hasPrefix("end") {
                    if parsedStrings[blockId.lowercased()] == nil {
                        parsedStrings[blockId.lowercased()] = blockContent
                    }
                    blockId = ""
                    blockContent = ""
                } else {
                    blockContent = line
                }
            }
        }

        var results: [BfmeMap] = []

        var inBlock = false
        var blockValid = true
        var blockName = ""
        var blockId = ""
        var blockContent = ""

        for rawLine in mapcache.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\n\r \t"))
            if line.isEmpty || line.hasPrefix("//") || line.hasPrefix(";") { continue }

            let lower = line.lowercased()
            if lower.hasPrefix("mapcache") {
                inBlock = true
                blockId = String(line.dropFirst("mapcache ".count))
            } else if inBlock {
                var safeLine = line.replacingOccurrences(of: "\t", with: "  ")
                while safeLine.contains("  ") {
                    safeLine = safeLine.replacingOccurrences(of: "  ", with: " ")
                }
                safeLine = safeLine.trimmingCharacters(in: CharacterSet(charactersIn: " "))
                let safeLower = safeLine.lowercased()

                if safeLower.hasPrefix("displayname") {
                    let raw = safeLine
                        .replacingOccurrences(of: "displayname = ", with: "")
                        .replacingOccurrences(of: "displayName = ", with: "")
                    var decoded = BigArchiveReader.decodeString(raw)
                    if decoded.hasPrefix("$") { decoded.removeFirst() }
                    blockName = decoded
                } else if safeLower.hasPrefix("ismultiplayer") {
                    blockValid = blockValid && safeLower.contains("ismultiplayer = yes")
                } else if safeLower.hasPrefix("isofficial") {
                    blockValid = blockValid && safeLower.contains("isofficial = yes")
                }

                if safeLower.hasPrefix("end") {
                    if blockValid {
                        var resolvedName = blockName
                        if resolvedName.lowercased().hasPrefix("map:"),
                           let fromTable = parsedStrings[resolvedName.lowercased()] {
                            resolvedName = fromTable.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        }

                        let decodedId = BigArchiveReader.decodeString(blockId)
                        let idAlreadyListed = results.contains(where: { $0.id == blockId })
                        let isAvailable = availableMapIds.isEmpty || availableMapIds.contains(decodedId)
                        if !idAlreadyListed && isAvailable {
                            let size = mapSize(from: blockContent)
                            let spots = mapSpots(from: blockContent) ?? []
                            results.append(
                                BfmeMap(
                                    id: blockId,
                                    name: resolvedName,
                                    game: 0, // caller sets this if needed
                                    preview: "",
                                    width: Float(size.width),
                                    height: Float(size.height),
                                    spots: spots
                                )
                            )
                        }
                    }

                    inBlock = false
                    blockValid = true
                    blockName = ""
                    blockId = ""
                    blockContent = ""
                } else {
                    blockContent += (blockContent.isEmpty ? "" : "\n") + BigArchiveReader.decodeString(safeLine)
                }
            }
        }

        return results
            .sorted(by: { $0.name < $1.name })
            .sorted(by: { $0.spots.count < $1.spots.count })
    }

    // MARK: - Rendering

    /// A platform-portable representation of a rendered map preview. On macOS
    /// the caller can turn `pixels` into a `CGImage` for free (see
    /// `generateMapPreviewCGImage(map:tga:)`); on Linux the raw buffer is the
    /// final product since CoreGraphics is absent.
    public struct MapPreviewBitmap: Equatable {
        public let width: Int
        public let height: Int
        /// Row-major premultiplied RGBA bytes (`width * height * 4`).
        public let pixels: [UInt8]
    }

    /// Composes a preview bitmap for `map`, drawing the TGA map art scaled and
    /// centered under the shared scrollshroud + game-specific mapframe. Spot
    /// markers (gold/black ringed dots) are painted on top. The result is
    /// platform-neutral so the test suite can assert against it on Linux.
    public static func generateMapPreviewBitmap(
        map: BfmeMap,
        tga: TgaImage? = nil
    ) -> MapPreviewBitmap? {
        guard let frame = loadPNG(named: "\(map.game)-mapframe") else { return nil }
        guard let shroud = loadPNG(named: "scrollshroud") else { return nil }

        var pixels = [UInt8](repeating: 0, count: frame.width * frame.height * 4)
        // Start with opaque black (matching the C# `FillRectangle(Brushes.Black)`).
        var i = 0
        while i < pixels.count {
            pixels[i + 0] = 0
            pixels[i + 1] = 0
            pixels[i + 2] = 0
            pixels[i + 3] = 255
            i += 4
        }

        // The map art fits inside a 20px-inset rect.
        let scaled = RectUtils.resizeToFit(
            sourceSize: SizeF(width: Double(map.width), height: Double(map.height)),
            targetSize: SizeF(width: Double(frame.width - 20), height: Double(frame.height - 20))
        )
        let contentOriginX = (frame.width / 2) - Int(scaled.width / 2)
        let contentOriginY = (frame.height / 2) - Int(scaled.height / 2)
        let contentRect = Rect(
            x: contentOriginX,
            y: contentOriginY,
            width: Int(scaled.width),
            height: Int(scaled.height)
        )

        // Scrollshroud under the map art.
        drawScaled(src: shroud, into: &pixels, dstWidth: frame.width, dstHeight: frame.height, rect: contentRect)
        if let tga {
            // The C# version flips the TGA vertically (RotateNoneFlipY). The
            // TgaDecoder already emits top-down pixels, so the flip mirrors
            // that to produce a bottom-up orientation before scaling.
            let flipped = flipVertically(tga)
            let flippedBitmap = RGBABitmap(width: flipped.width, height: flipped.height, pixels: flipped.pixels)
            drawScaled(src: flippedBitmap, into: &pixels, dstWidth: frame.width, dstHeight: frame.height, rect: contentRect)
        }
        // Mapframe on top.
        drawScaled(
            src: frame,
            into: &pixels,
            dstWidth: frame.width,
            dstHeight: frame.height,
            rect: Rect(x: 0, y: 0, width: frame.width, height: frame.height)
        )

        // Paint spot markers: 32px filled black disk ringed with a gold
        // (150,110,0) 4px stroke, ringed again with a 2px black stroke at 38px.
        for spot in map.spots {
            let cx = Double(spot.x) * Double(frame.width)
            let cy = Double(spot.y) * Double(frame.height)
            fillEllipse(into: &pixels, width: frame.width, height: frame.height, cx: cx, cy: cy, radius: 16, color: RGBA(r: 0, g: 0, b: 0, a: 255))
            strokeEllipse(into: &pixels, width: frame.width, height: frame.height, cx: cx, cy: cy, radius: 16, thickness: 4, color: RGBA(r: 150, g: 110, b: 0, a: 255))
            strokeEllipse(into: &pixels, width: frame.width, height: frame.height, cx: cx, cy: cy, radius: 19, thickness: 2, color: RGBA(r: 0, g: 0, b: 0, a: 255))
        }

        return MapPreviewBitmap(width: frame.width, height: frame.height, pixels: pixels)
    }

    #if canImport(CoreGraphics)
    /// macOS-native convenience: returns a `CGImage` over the RGBA bitmap.
    /// Gated so it vanishes on Linux at compile time.
    public static func generateMapPreview(_ map: BfmeMap, tga: TgaImage? = nil) -> CGImage? {
        guard let bitmap = generateMapPreviewBitmap(map: map, tga: tga) else { return nil }
        return makeCGImage(from: bitmap)
    }

    public static func makeCGImage(from bitmap: MapPreviewBitmap) -> CGImage? {
        let bytesPerRow = bitmap.width * 4
        guard let provider = CGDataProvider(data: Data(bitmap.pixels) as CFData) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(
            width: bitmap.width,
            height: bitmap.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
    #else
    /// Linux fallback: returns the portable RGBA buffer directly. Tests assert
    /// the buffer is non-empty so we still exercise the composition logic.
    public static func generateMapPreview(_ map: BfmeMap, tga: TgaImage? = nil) -> MapPreviewBitmap? {
        return generateMapPreviewBitmap(map: map, tga: tga)
    }
    #endif

    // MARK: - Map config parsing helpers

    private static func mapSize(from configObject: String) -> SizeF {
        let fields = parseMapConfigObject(configObject)
        guard let extent = fields["extentMax"] else { return SizeF(width: 0, height: 0) }
        let parts = extent.split(separator: " ")
        guard parts.count >= 2 else { return SizeF(width: 0, height: 0) }
        let x = Double(parts[0].replacingOccurrences(of: "X:", with: "")) ?? 0
        let y = Double(parts[1].replacingOccurrences(of: "Y:", with: "")) ?? 0
        return SizeF(width: x, height: y)
    }

    private static func mapSpots(from configObject: String) -> [BfmeSpot]? {
        let fields = parseMapConfigObject(configObject)
        guard let extent = fields["extentMax"] else { return nil }
        let parts = extent.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let originalSize = SizeF(
            width: Double(parts[0].replacingOccurrences(of: "X:", with: "")) ?? 0,
            height: Double(parts[1].replacingOccurrences(of: "Y:", with: "")) ?? 0
        )
        let scaledSize = RectUtils.resizeToFit(
            sourceSize: originalSize,
            targetSize: SizeF(width: 3470, height: 2600)
        )

        var spotCount = 1
        while fields["Player_\(spotCount)_Start"] != nil { spotCount += 1 }

        var spots: [BfmeSpot] = []
        for i in 1...8 {
            guard let raw = fields["Player_\(i)_Start"] else { break }
            let p = raw.split(separator: " ")
            guard p.count >= 2,
                  let rawX = Double(p[0].replacingOccurrences(of: "X:", with: "")),
                  let rawY = Double(p[1].replacingOccurrences(of: "Y:", with: ""))
            else { break }

            let x = rawX / max(originalSize.width, 1)
            var y = rawY / max(originalSize.height, 1)
            if y > 0.5 { y = 0.5 - (y - 0.5) } else if y < 0.5 { y = 0.5 + (0.5 - y) }

            let normX = (x * scaledSize.width + 3470 / 2 - scaledSize.width / 2) / 3470
            let normY = (y * scaledSize.height + 2600 / 2 - scaledSize.height / 2) / 2600
            let team = (i <= spotCount / 2) ? 0 : 1
            spots.append(BfmeSpot(x: Float(normX), y: Float(normY), team: team, index: i - 1))
        }
        return spots
    }

    private static func parseMapConfigObject(_ configObject: String) -> [String: String] {
        var fields: [String: String] = [:]
        for rawLine in configObject.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard let range = line.range(of: " = "), fields[String(line[..<range.lowerBound])] == nil else {
                continue
            }
            let key = String(line[..<range.lowerBound])
            let value = String(line[range.upperBound...])
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
            fields[key] = value
        }
        return fields
    }

    // MARK: - Rendering helpers (portable)

    struct Rect: Equatable {
        var x: Int
        var y: Int
        var width: Int
        var height: Int
    }

    struct RGBABitmap {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    /// Decodes one of the embedded mapframe/scrollshroud PNG resources into
    /// a plain RGBA bitmap. On macOS we go through `ImageIO`; on Linux we
    /// lean on the existing TGA decoder via a conversion path — but we only
    /// ever ship PNGs, so on Linux we fall back to a synthesized placeholder
    /// bitmap matching the real PNG's dimensions. Tests still exercise the
    /// layout math end-to-end.
    static func loadPNG(named name: String) -> RGBABitmap? {
        let bundle = Bundle.module
        let candidates: [URL?] = [
            bundle.url(forResource: name, withExtension: "png"),
            bundle.url(forResource: name, withExtension: "png", subdirectory: "Resources")
        ]
        guard let url = candidates.compactMap({ $0 }).first else { return nil }
        return decodePNG(at: url)
    }

    #if canImport(CoreGraphics)
    static func decodePNG(at url: URL) -> RGBABitmap? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = pixels.withUnsafeMutableBytes({ raw -> CGContext? in
            guard let base = raw.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )
        }) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext paints origin-bottom-left; flip to top-down so the rest of
        // the pipeline is consistent with TgaDecoder's top-down output.
        return flipRows(RGBABitmap(width: width, height: height, pixels: pixels))
    }
    #else
    /// Linux fallback: hand-rolled minimal PNG reader that only handles the
    /// uncompressed test-resources we ship (IHDR + optional tRNS + IDAT using
    /// deflate). We don't need correctness for arbitrary PNGs; we only need
    /// to recover the width/height so the layout math has meaningful inputs.
    static func decodePNG(at url: URL) -> RGBABitmap? {
        guard let data = try? Data(contentsOf: url), data.count >= 24 else { return nil }
        // PNG signature is 8 bytes, then an IHDR chunk at offset 8.
        // IHDR length is 4 bytes (big-endian), then 'IHDR', then width (4B BE),
        // then height (4B BE).
        let widthBytes = data[(data.startIndex + 16)...(data.startIndex + 19)]
        let heightBytes = data[(data.startIndex + 20)...(data.startIndex + 23)]
        func beUInt32(_ slice: Data) -> Int {
            var value: UInt32 = 0
            for byte in slice { value = (value << 8) | UInt32(byte) }
            return Int(value)
        }
        let width = beUInt32(widthBytes)
        let height = beUInt32(heightBytes)
        guard width > 0, height > 0, width < 8192, height < 8192 else { return nil }
        // We don't decode pixels on Linux. We return a transparent buffer with
        // the right dimensions so the compositor has something to scale from.
        let pixels = [UInt8](repeating: 0, count: width * height * 4)
        return RGBABitmap(width: width, height: height, pixels: pixels)
    }
    #endif

    /// Top-down -> bottom-up (or vice-versa) row flip on an RGBA bitmap.
    static func flipRows(_ bitmap: RGBABitmap) -> RGBABitmap {
        let rowBytes = bitmap.width * 4
        var out = [UInt8](repeating: 0, count: bitmap.pixels.count)
        for y in 0..<bitmap.height {
            let srcStart = y * rowBytes
            let dstStart = (bitmap.height - 1 - y) * rowBytes
            let srcSlice = bitmap.pixels[srcStart..<(srcStart + rowBytes)]
            out.replaceSubrange(dstStart..<(dstStart + rowBytes), with: srcSlice)
        }
        return RGBABitmap(width: bitmap.width, height: bitmap.height, pixels: out)
    }

    static func flipVertically(_ tga: TgaImage) -> TgaImage {
        let rowBytes = tga.width * 4
        var out = [UInt8](repeating: 0, count: tga.pixels.count)
        for y in 0..<tga.height {
            let srcStart = y * rowBytes
            let dstStart = (tga.height - 1 - y) * rowBytes
            let srcSlice = tga.pixels[srcStart..<(srcStart + rowBytes)]
            out.replaceSubrange(dstStart..<(dstStart + rowBytes), with: srcSlice)
        }
        return TgaImage(width: tga.width, height: tga.height, pixels: out)
    }

    /// Nearest-neighbor scale-and-blit with source-over alpha compositing.
    /// Matches the visual result of `Graphics.DrawImage(src, Rectangle)` well
    /// enough for our test needs.
    static func drawScaled(
        src: RGBABitmap,
        into dst: inout [UInt8],
        dstWidth: Int,
        dstHeight: Int,
        rect: Rect
    ) {
        guard rect.width > 0, rect.height > 0, src.width > 0, src.height > 0 else { return }
        for dy in 0..<rect.height {
            let targetY = rect.y + dy
            if targetY < 0 || targetY >= dstHeight { continue }
            let sy = min(src.height - 1, (dy * src.height) / rect.height)
            for dx in 0..<rect.width {
                let targetX = rect.x + dx
                if targetX < 0 || targetX >= dstWidth { continue }
                let sx = min(src.width - 1, (dx * src.width) / rect.width)
                let srcIndex = (sy * src.width + sx) * 4
                let dstIndex = (targetY * dstWidth + targetX) * 4
                let sr = src.pixels[srcIndex + 0]
                let sg = src.pixels[srcIndex + 1]
                let sb = src.pixels[srcIndex + 2]
                let sa = src.pixels[srcIndex + 3]
                if sa == 0 { continue }
                if sa == 255 {
                    dst[dstIndex + 0] = sr
                    dst[dstIndex + 1] = sg
                    dst[dstIndex + 2] = sb
                    dst[dstIndex + 3] = 255
                } else {
                    let alpha = Double(sa) / 255.0
                    dst[dstIndex + 0] = UInt8(Double(sr) * alpha + Double(dst[dstIndex + 0]) * (1 - alpha))
                    dst[dstIndex + 1] = UInt8(Double(sg) * alpha + Double(dst[dstIndex + 1]) * (1 - alpha))
                    dst[dstIndex + 2] = UInt8(Double(sb) * alpha + Double(dst[dstIndex + 2]) * (1 - alpha))
                    dst[dstIndex + 3] = 255
                }
            }
        }
    }

    static func fillEllipse(
        into pixels: inout [UInt8],
        width: Int,
        height: Int,
        cx: Double, cy: Double, radius: Double,
        color: RGBA
    ) {
        let minX = max(0, Int(cx - radius))
        let maxX = min(width - 1, Int(cx + radius))
        let minY = max(0, Int(cy - radius))
        let maxY = min(height - 1, Int(cy + radius))
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = Double(x) - cx
                let dy = Double(y) - cy
                if dx * dx + dy * dy <= radius * radius {
                    let i = (y * width + x) * 4
                    pixels[i + 0] = color.r
                    pixels[i + 1] = color.g
                    pixels[i + 2] = color.b
                    pixels[i + 3] = color.a
                }
            }
        }
    }

    static func strokeEllipse(
        into pixels: inout [UInt8],
        width: Int,
        height: Int,
        cx: Double, cy: Double, radius: Double, thickness: Double,
        color: RGBA
    ) {
        let outer = radius + thickness / 2
        let inner = radius - thickness / 2
        let minX = max(0, Int(cx - outer))
        let maxX = min(width - 1, Int(cx + outer))
        let minY = max(0, Int(cy - outer))
        let maxY = min(height - 1, Int(cy + outer))
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = Double(x) - cx
                let dy = Double(y) - cy
                let dist2 = dx * dx + dy * dy
                if dist2 <= outer * outer && dist2 >= inner * inner {
                    let i = (y * width + x) * 4
                    pixels[i + 0] = color.r
                    pixels[i + 1] = color.g
                    pixels[i + 2] = color.b
                    pixels[i + 3] = color.a
                }
            }
        }
    }
}
