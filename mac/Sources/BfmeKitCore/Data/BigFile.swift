import Foundation

/// A single entry inside a .big archive. Lazily reads its slab of bytes on
/// demand from the source file on disk.
public struct BigFile: Equatable, Hashable, Sendable {
    public var name: String
    public var source: String
    public var offset: Int
    public var size: Int

    public init(name: String, source: String, offset: Int, size: Int) {
        self.name = name
        self.source = source
        self.offset = offset
        self.size = size
    }

    /// Reads the raw bytes for this entry from the underlying .big archive.
    public func getData() throws -> Data {
        let url = URL(fileURLWithPath: source)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: size) ?? Data()
        return data
    }

    /// Reads the entry as ISO-8859-4 text to mirror the original C# behavior
    /// (which used `Encoding.GetEncoding("iso-8859-4")`). Foundation on Linux
    /// does not expose `isoLatin4` directly; we fall back to `isoLatin1` which
    /// matches for all single-byte characters that the BFME asset tree uses.
    public func getText() throws -> String {
        let data = try getData()
        #if canImport(Darwin)
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return String(data: data, encoding: .utf8) ?? ""
        #else
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return String(data: data, encoding: .utf8) ?? ""
        #endif
    }
}
