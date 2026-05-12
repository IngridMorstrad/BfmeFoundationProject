import Foundation

/// A plain 8-bit per channel RGBA pixel. The original C# tree reached for
/// `System.Drawing.Color`; macOS/Linux have no equivalent so every color value
/// in the port flows through this value type.
public struct RGBA: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Convenience constructor that packs the 0xAARRGGBB layout used by the
    /// BIG/TGA/CSF code paths.
    public init(argb: UInt32) {
        self.a = UInt8((argb >> 24) & 0xFF)
        self.r = UInt8((argb >> 16) & 0xFF)
        self.g = UInt8((argb >> 8) & 0xFF)
        self.b = UInt8(argb & 0xFF)
    }

    public var argb: UInt32 {
        return (UInt32(a) << 24) | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
    }
}
