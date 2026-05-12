import Foundation
import CZlib

/// Minimal gzip/deflate helpers implemented on top of the system `zlib`.
/// Only the operations needed by `HttpMarshal.b64-gzip` are exposed.
public enum GzipDecoder {
    public enum GzipError: Error {
        case initFailed(Int32)
        case inflateFailed(Int32, String?)
    }

    /// Decompresses a gzip-wrapped byte buffer.
    public static func decompress(_ data: Data) throws -> Data {
        if data.isEmpty { return Data() }

        var stream = z_stream()
        stream.next_in = nil
        stream.avail_in = 0
        stream.total_in = 0
        stream.next_out = nil
        stream.avail_out = 0
        stream.total_out = 0
        stream.msg = nil
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        // 15 window bits + 32 enables automatic gzip/zlib header detection.
        let windowBits: Int32 = 15 + 32
        let initStatus = inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { throw GzipError.initFailed(initStatus) }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunkSize = 16 * 1024

        return try data.withUnsafeBytes { (inputRaw: UnsafeRawBufferPointer) -> Data in
            guard let inputBase = inputRaw.baseAddress else { return Data() }
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: inputBase.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = UInt32(data.count)

            var outputBuffer = [UInt8](repeating: 0, count: chunkSize)
            while true {
                let status: Int32 = outputBuffer.withUnsafeMutableBufferPointer { buf -> Int32 in
                    guard let base = buf.baseAddress else { return Z_BUF_ERROR }
                    stream.next_out = base
                    stream.avail_out = UInt32(buf.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }

                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(contentsOf: outputBuffer.prefix(produced))
                }

                if status == Z_STREAM_END { break }
                if status != Z_OK {
                    let message = stream.msg.flatMap { String(cString: $0) }
                    throw GzipError.inflateFailed(status, message)
                }
                if stream.avail_in == 0 && stream.avail_out != 0 {
                    // No more input and zlib produced nothing this pass: we're done.
                    break
                }
            }
            return output
        }
    }

    /// Compresses a buffer to gzip. Primarily a test helper so the b64-gzip
    /// round-trip test can construct a real gzipped payload without shelling
    /// out to the `gzip` binary.
    public static func compress(_ data: Data) throws -> Data {
        if data.isEmpty { return Data() }

        var stream = z_stream()
        stream.next_in = nil
        stream.avail_in = 0
        stream.total_in = 0
        stream.next_out = nil
        stream.avail_out = 0
        stream.total_out = 0
        stream.msg = nil
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        // 15 window bits + 16 selects the gzip wrapper.
        let windowBits: Int32 = 15 + 16
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            windowBits,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else { throw GzipError.initFailed(initStatus) }
        defer { deflateEnd(&stream) }

        var output = Data()
        let chunkSize = 16 * 1024

        return try data.withUnsafeBytes { (inputRaw: UnsafeRawBufferPointer) -> Data in
            guard let inputBase = inputRaw.baseAddress else { return Data() }
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: inputBase.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = UInt32(data.count)

            var outputBuffer = [UInt8](repeating: 0, count: chunkSize)
            while true {
                let status: Int32 = outputBuffer.withUnsafeMutableBufferPointer { buf -> Int32 in
                    guard let base = buf.baseAddress else { return Z_BUF_ERROR }
                    stream.next_out = base
                    stream.avail_out = UInt32(buf.count)
                    return deflate(&stream, Z_FINISH)
                }

                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(contentsOf: outputBuffer.prefix(produced))
                }

                if status == Z_STREAM_END { break }
                if status != Z_OK {
                    let message = stream.msg.flatMap { String(cString: $0) }
                    throw GzipError.inflateFailed(status, message)
                }
            }
            return output
        }
    }
}
