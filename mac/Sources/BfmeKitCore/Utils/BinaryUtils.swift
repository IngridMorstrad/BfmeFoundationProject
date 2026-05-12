import Foundation

/// Tiny cursor over a `Data` buffer that mirrors the tight subset of
/// `BinaryReader` used by the original C# tree (BIG archive + CSF).
public struct BinaryReader {
    public let data: Data
    public private(set) var position: Int

    public init(_ data: Data) {
        self.data = data
        self.position = 0
    }

    public var length: Int { data.count }
    public var remaining: Int { data.count - position }

    public mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, position + count <= data.count else {
            throw BinaryUtilsError.endOfStream
        }
        let start = data.startIndex + position
        let slice = data.subdata(in: start..<(start + count))
        position += count
        return slice
    }

    public mutating func readUInt8() throws -> UInt8 {
        let slice = try readBytes(1)
        return slice[slice.startIndex]
    }

    public mutating func readUInt32LE() throws -> UInt32 {
        let bytes = try readBytes(4)
        return bytes.withUnsafeBytes { raw -> UInt32 in
            let u0 = UInt32(raw[0])
            let u1 = UInt32(raw[1]) << 8
            let u2 = UInt32(raw[2]) << 16
            let u3 = UInt32(raw[3]) << 24
            return u0 | u1 | u2 | u3
        }
    }

    public mutating func readUInt32BE() throws -> UInt32 {
        let bytes = try readBytes(4)
        return bytes.withUnsafeBytes { raw -> UInt32 in
            let u0 = UInt32(raw[0]) << 24
            let u1 = UInt32(raw[1]) << 16
            let u2 = UInt32(raw[2]) << 8
            let u3 = UInt32(raw[3])
            return u0 | u1 | u2 | u3
        }
    }

    /// Reads a null-terminated ASCII/latin-1 string. The terminator is
    /// consumed but not included in the returned string.
    public mutating func readNullTerminatedString() throws -> String {
        var bytes: [UInt8] = []
        while true {
            let b = try readUInt8()
            if b == 0 { break }
            bytes.append(b)
        }
        return String(bytes: bytes, encoding: .isoLatin1) ?? String(decoding: bytes, as: UTF8.self)
    }

    public mutating func readFixedLengthString(_ count: Int) throws -> String {
        if count == 0 { return "" }
        let bytes = try readBytes(count)
        return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1) ?? ""
    }

    /// Reads a CSF-style inverted UTF-16LE string: each byte is bit-wise
    /// complemented before decoding.
    public mutating func readFixedLengthStringUnicode(_ count: Int) throws -> String {
        if count == 0 { return "" }
        var bytes = [UInt8](try readBytes(count * 2))
        for i in 0..<bytes.count { bytes[i] = ~bytes[i] }
        return bytes.withUnsafeBufferPointer { buf -> String in
            guard let base = buf.baseAddress else { return "" }
            // UTF-16LE, little-endian by construction (CSF format).
            let scalars: [UInt16] = stride(from: 0, to: buf.count, by: 2).map { i -> UInt16 in
                let low = UInt16(base[i])
                let high = i + 1 < buf.count ? UInt16(base[i + 1]) : 0
                return (high << 8) | low
            }
            return String(decoding: scalars, as: UTF16.self)
        }
    }
}

public enum BinaryUtilsError: Error, Equatable {
    case endOfStream
}

public enum BinaryUtils {
    public static func writeUInt32BE(_ value: UInt32) -> Data {
        var out = Data(count: 4)
        out[0] = UInt8((value >> 24) & 0xFF)
        out[1] = UInt8((value >> 16) & 0xFF)
        out[2] = UInt8((value >> 8) & 0xFF)
        out[3] = UInt8(value & 0xFF)
        return out
    }

    public static func writeUInt32LE(_ value: UInt32) -> Data {
        var out = Data(count: 4)
        out[0] = UInt8(value & 0xFF)
        out[1] = UInt8((value >> 8) & 0xFF)
        out[2] = UInt8((value >> 16) & 0xFF)
        out[3] = UInt8((value >> 24) & 0xFF)
        return out
    }
}
